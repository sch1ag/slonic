package Slonic::Config;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Carp qw(croak);
use Slonic::Utils qw(read_json_from_file);
use Data::Dumper;
use Log::Any qw($log);

sub new {
    my ($class, $cfgname) = @_;
    my $self = {};
  
    croak($log->fatal("Configuration name is not defined.")) unless defined $cfgname;
    
    $self->{'CFGNAME'} = $cfgname;
    $self->{'CFG_FILENAME_POSTFIX'} = "json";
    $self->{'CONF'} = {};
    bless ($self, $class);

    $self->{'CONF'}->{'SLONIC_HOME'}=$self->_get_dirpath_from_env('SLONIC_HOME');
    $self->{'CONF'}->{'SLONIC_ETC'}=$self->_get_dirpath_from_env('SLONIC_ETC');
    $self->{'CONF'}->{'SLONIC_VAR'}=$self->_get_dirpath_from_env('SLONIC_VAR');

    #read default config from etc subdir of SLONIC_HOME
    my $conf_dir = $self->{'CONF'}->{'SLONIC_HOME'} . "/etc";
    (-d $conf_dir) || croak $log->fatal("No default config directory $conf_dir found.");
    $self->_get_cfg_from_dir($conf_dir);

    #read custom config from SLONIC_ETC
    $self->_get_cfg_from_dir($self->{'CONF'}->{'SLONIC_ETC'});
    $log->debug("Config:", $self->{'CONF'});

    return $self;
}

sub _get_dirpath_from_env
{
    my $self=shift;
    my $envname=shift;

    my $dirname;

    if (defined $ENV{$envname})
    {
        $dirname = $ENV{$envname};
        (-d $dirname) || croak $log->fatal("$envname is set to $dirname. But $dirname is not a directory.");
        return $dirname;
    }
    else
    {
        croak $log->fatal("Environment variable $envname is not set.");
    }
}

sub _get_cfg_from_dir {
    my $self = shift;
    my $cfg_dir = shift;

    $log->debug("Config is $self->{CFGNAME}");
    my @cfg_parts = split('\.', $self->{CFGNAME});
    my $n_levels = scalar @cfg_parts;

    for (my $i=0; $i < $n_levels; $i++){
        my $filepath = join('/', $cfg_dir, join('.', @cfg_parts[0 .. $i], $self->{CFG_FILENAME_POSTFIX}));
        if (-f $filepath){
            $log->debug("Reading config from $filepath");
            my $cfg_ff = read_json_from_file($filepath);
            $self->_update_cfg($cfg_ff);
        }
    }
}

sub _update_cfg {
    my $self = shift;
    my $add_cfg = shift;
    for my $prop_name (keys %{$add_cfg})
    {
        $self->{CONF}->{$prop_name} = $add_cfg->{$prop_name};
    }
}

1;
