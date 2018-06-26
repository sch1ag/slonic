package Slonic::ChiefOrder;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.1';

use Carp qw(croak);
use Slonic::Utils qw(read_json_from_file check_true check_false);
use Slonic::CondChecker qw(check_condition);
use Proc::Background;
use Data::Dumper;
use Log::Any qw($log);

sub new {
    my ($class, $CONF, $name, $osdata) = @_;
    my $self = {};
    
    $self->{CONF} = $CONF; 
    $self->{NAME} = $name;
    $self->{OSDATA} = $osdata;
    $self->{START_CFG} = {}; 
    $self->{DOSTART} = 0; 
    $self->{PROC} = undef; 
    bless ($self, $class);

    my $def_abs_orders_dir = join('/', $CONF->{SLONIC_HOME}, "etc", $self->{CONF}->{REL_ORDERS_DIRNAME});
    $self->_get_cfg_from_dir($def_abs_orders_dir);
    my $cust_abs_orders_dir = join('/', $CONF->{SLONIC_ETC}, $self->{CONF}->{REL_ORDERS_DIRNAME});
    $self->_get_cfg_from_dir($cust_abs_orders_dir);

    $log->debug("Start config for order $self->{NAME}:", $self->{START_CFG});
    $self->{DOSTART} = $self->_check_start_cond();
    $log->debug("Start decision for order $self->{NAME}:", $self->{DOSTART});
    return $self;
}

sub _check_start_cond {
    my $self = shift;
    my $chief_profiles = shift;

    if (exists $self->{'START_CFG'}{'FORCE_SWITCH'}) {
        if (check_true($self->{'START_CFG'}{'FORCE_SWITCH'}))
        {
            return 1;
        }
        elsif (check_false($self->{'START_CFG'}{'FORCE_SWITCH'}))
        {
            return 0;
        }
    } 

    my $prof_match = 0;
    for my $chief_prof (@{$self->{CONF}{PROFILES}})
    {
        if (grep {$_ eq $chief_prof} @{$self->{START_CFG}{PROFILES}})
        {
            $prof_match = 1;
            last;
        }
    }
    return $prof_match && check_condition($self->{OSDATA}, $self->{START_CFG}{CONDITION});
}

sub _get_cfg_from_dir {
    my $self = shift;
    my $cfg_dir = shift;

    my $filepath = join('/', $cfg_dir, $self->{NAME});
    if (-f $filepath){
            $log->debug("Using file $filepath as order $self->{NAME} start config file.");
            my $cfg_ff = read_json_from_file($filepath);
            $self->_update_cfg($cfg_ff);
    }
}

sub _update_cfg {
    my $self = shift;
    my $add_cfg = shift;
    for my $prop_name (keys %{$add_cfg})
    {
        $self->{START_CFG}->{$prop_name} = $add_cfg->{$prop_name};
    }
}

sub start {
    my $self = shift;
    my $ret = 0;

    if ($self->{DOSTART})
    {
        my $abspath = join('/', $self->{CONF}->{SLONIC_HOME}, "bin", $self->{START_CFG}{SCRIPT});
        my $command = $abspath." ".$self->{START_CFG}{CFG_NAME};
        $self->{PROC} = Proc::Background->new($command);
        $ret = 1;
    }
    return $ret;
}

sub check {
    my $self = shift;
    my $ret = 0;
    if (defined $self->{PROC}){
        $ret = $self->{PROC}->alive(); 
    }
    return $ret;
}

1;
