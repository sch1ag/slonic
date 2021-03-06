#!/usr/bin/perl -w
# SimpLe ONline Information Collector: slonic courier

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use IO::Select;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Slonic::Utils qw( select_abs_path );
use Slonic::SafeFileChannel;
use Slonic::InfluxDBConn;
use Slonic::Config;
use Slonic::ElementDispenser;
use Slonic::Sleepyhead;

use Data::Dumper;

use Carp qw(croak);
use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

my $CFGNAME = $ARGV[0]; 
my $CFGOBJ = Slonic::Config->new($CFGNAME);
my $CONF = $CFGOBJ->{CONF};

$log->notice("Starting normally with config $CFGNAME");

my $run = 1;

$SIG{USR1} = \&sig_usr;

#prepare InfluxDB connection
my $idbconn = Slonic::InfluxDBConn->new(
                                           {
                                                idb_host => $CONF->{'IDB_HOST'},
                                                idb_dbname => $CONF->{'IDB_DB'},
                                                idb_port => $CONF->{'IDB_PORT'},
                                                idb_user => $CONF->{'IDB_USER'},
                                                idb_password => $CONF->{'IDB_PASSWORD'},
                                                idb_precision => 's',
                                                idb_consistency => $CONF->{'IDB_CONSISTENCY'},
                                                http_keep_alive => 1,
                                                http_timeout => $CONF->{'IDB_TIMEOUT'}
                                           }
                                       );

#prepare ElementDispenser to group lines from channels to bunches of reasonable for IDB size
my $linesdispenser = Slonic::ElementDispenser->new({'recipient' => sub { $idbconn->write_data(@_) }, 'portion' => $CONF->{'IDB_MAX_ROWS_PER_REQ'}});

my @sfc_chans;
my $sfc_chans_update_counter=$CONF->{'UPDATE_CHANNELS_LIST_CYCLE'};

my $sleepyhead = Slonic::Sleepyhead->new($CONF->{'SEND_DATA_INTERVAL_TARGET'});
$sleepyhead->sleep_rest_of_cycle();

#read all data from all channels and post it to idb
while ($run){
    $sleepyhead->sleep_rest_of_cycle();

    #Create/update SafeFileChannel objects
    if($sfc_chans_update_counter == $CONF->{'UPDATE_CHANNELS_LIST_CYCLE'}){
        @sfc_chans = create_channels($CONF);
        $sfc_chans_update_counter=0;
    }
    $sfc_chans_update_counter++;

    my $channels_has_data = 1;
    while ($channels_has_data > 0) 
    {
        $channels_has_data = 0;
        for my $sfc_chan (@sfc_chans)
        {
            my ($dataref_from_chan, $has_more_data) = $sfc_chan->read_part_and_truncate_if_no_more_data($CONF->{CHANNEL_READ_PORTION});

            $log->debug("Got " . @{$dataref_from_chan} . " lines from $sfc_chan->{'FILENAME'}");

            $channels_has_data += $has_more_data;
    
            $linesdispenser->add_elements($dataref_from_chan);
        }
    }

    $linesdispenser->flush_buffer();
}

exit(0);

sub sig_usr {
    $run=0;
}

# return array of references of the SafeFileChannel objects
sub create_channels {
    my $CONF = shift;
    my @sfc_objs;

    my $dirpath = select_abs_path($CONF, 'SLONIC_VAR', 'CHANNELS_DIR');
 
    opendir(my $dh, $dirpath) || croak $log->fatal("Can't opendir $dirpath: $!");
    my @chan_files = grep { /^$CONF->{CHANNEL_NAME}\..*\.slmc$/ && -f "$dirpath/$_" } readdir($dh);
    closedir $dh;

    for my $fl (@chan_files){
        my $file_pathname="$dirpath/$fl";
        my $objparams = {
                            filename=>"$file_pathname",
                            lockretry=>$CONF->{'MOD_CHANNEL_LOCK_ATTEMPTS'},
                            lockwaittime=>$CONF->{'MOD_WAIT_BETWEEN_CHANNEL_LOCK_ATTEMPTS'},
                            maxfilesize=>0
                        };
        my $sfc_obj = Slonic::SafeFileChannel->new($objparams);
        if ($sfc_obj->delete_if_empty()){
            push(@sfc_objs, $sfc_obj);
        }
    }
    return @sfc_objs;
}

