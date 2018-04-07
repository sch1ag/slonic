package Slonic::M2DChannel;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Data::Dumper;
use Sys::Hostname;
use FindBin qw($Script);
use File::Basename;
use Carp qw(croak);
use Slonic::SafeFileChannel;
use Slonic::Utils qw(select_abs_path);
use InfluxDB::LineProtocol qw(data2line);
#use InfluxDB::LineProtocol;
#InfluxDB::LineProtocol->import(qw(data2line precision=s));
use Log::Any '$log';

sub new {
    my ($class, $CONF) = @_;
    my $self = {};

    my $cur_procpid=$$;
    my $cur_scriptname=$Script;

    $self->{CHANNELS} = {};
    $self->{CHANNELS_DATA} = {};
    $self->{MAX_CHANNEL_DATA_BUFFER_ROWS} = $CONF->{'MAX_CHANNEL_DATA_BUFFER_ROWS'};
   
    my @ch_names = @{$CONF->{MOD_CHANNELS}};
    my $channel_basefilename;
    my $channel_pathfilename;
    for my $ch_name (@ch_names){

        $channel_basefilename = $ch_name . "." . basename($cur_scriptname) . "_" . $cur_procpid . ".slmc";
        $channel_pathfilename = select_abs_path($CONF, 'SLONIC_VAR', 'CHANNELS_DIR')."/".$channel_basefilename ;
        my $channel = Slonic::SafeFileChannel->new({
                                                             filename=>"$channel_pathfilename", 
                                                             lockretry=>$CONF->{'MOD_CHANNEL_LOCK_ATTEMPTS'}, 
                                                             lockwaittime=>$CONF->{'MOD_WAIT_BETWEEN_CHANNEL_LOCK_ATTEMPTS'},
                                                             maxfilesize=>$CONF->{'MOD_CHANNEL_MAX_SIZE_MB'}*1024*1024
                                                    });
        $self->{CHANNELS}->{$ch_name}=$channel;
        $self->{CHANNELS_DATA}->{$ch_name} = [];
    }

    #tags
    $self->{STD_TAGS}={hostname => hostname, interval => $CONF->{'INTERVAL'}};
    $log->debug("Standart tags (hardcoded) is: ", $self->{STD_TAGS});

    $self->{CUSTOM_TAGS} = $CONF->{TAGS};
    $log->debug("Custom tags is: ", $self->{CUSTOM_TAGS});

    my @ENV_TAG_KEYS = grep { $_ =~ /^SLONIC_TAG_/ } keys %ENV;
    my %ENV_TAGS = map {substr($_, 11) => $ENV{$_}} @ENV_TAG_KEYS;
    $self->{ENV_TAGS} = \%ENV_TAGS;
    $log->debug("Environment tags is: ", $self->{ENV_TAGS});

    bless($self, $class);
    return $self;
}

sub send {
    my $self = shift;
    my $indata = shift;
    #print "DEBUG: indata ".Dumper($indata);

    #preparing idb lines and pushing it to data array for every channel
    for my $dataline (@{$indata}){
        my ($mname, $valsref, $tagsref, $timestamp) = @{$dataline};
    
        #lets merge all defined tags
        my %merged_tags;
        for my $href ($tagsref, $self->{STD_TAGS}, $self->{CUSTOM_TAGS}, $self->{ENV_TAGS})
        {
            if (defined $href)
            {
                for my $key (keys %{$href})
                {
                    $merged_tags{$key}=$href->{$key};
                }
            }
        }
 
        my $idbline=data2line($mname, $valsref, \%merged_tags, $timestamp); 
 
        for my $cur_channame (keys %{$self->{CHANNELS}}){
            push(@{$self->{CHANNELS_DATA}->{$cur_channame}}, $idbline);
        }
    }

    for my $cur_channame (keys %{$self->{CHANNELS}}){
        my $ch_data_size=scalar @{$self->{CHANNELS_DATA}->{$cur_channame}};
        if ($ch_data_size){
            if ($self->{CHANNELS}->{$cur_channame}->append($self->{CHANNELS_DATA}->{$cur_channame})){
                $self->{CHANNELS_DATA}->{$cur_channame} = [];
            }
            elsif($self->{'MAX_CHANNEL_DATA_BUFFER_ROWS'} && $ch_data_size>=$self->{'MAX_CHANNEL_DATA_BUFFER_ROWS'})
            {
                $log->warn("M2D channel $cur_channame data buffer size is $ch_data_size rows exceeds configured MAX_CHANNEL_DATA_BUFFER_ROWS. Clearing buffer.");
                $self->{CHANNELS_DATA}->{$cur_channame}=[];
            }
        }
    }
    #print "DEBUG: idblines ".Dumper($self->{DATA});
}

1;
