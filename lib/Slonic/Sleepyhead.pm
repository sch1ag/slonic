package Slonic::Sleepyhead;

use vars;
use strict;
use warnings;

use Carp qw(croak);
use Log::Any qw($log);
use Time::HiRes qw( time sleep );


sub new {
    my ($class, $target_cycle_duration) = @_;
    my $self = {};

    $self->{'TARGET_CYCLE_DURATION'} = 0;
    $self->{'TARGET_CYCLE_DURATION'} = $target_cycle_duration if defined $target_cycle_duration;
    $self->{'CYCLE_START_TIME'} = time();

    bless($self, $class);
    return $self;
}

sub sleep_rest_of_cycle
{
    my ($self, $target_cycle_duration) = @_;
    $target_cycle_duration = $self->{'TARGET_CYCLE_DURATION'} unless defined $target_cycle_duration;
    my $current_time = time();
    my $already_spend_time = $current_time - $self->{'CYCLE_START_TIME'};
    my $sleep_time = ($already_spend_time < $target_cycle_duration) ? $target_cycle_duration - $already_spend_time : 0 ;
    $log->debug("Cycle with target duration of $target_cycle_duration seconds takes $already_spend_time to complete. Will go to sleep for $sleep_time seconds.");
    sleep $sleep_time;
    $self->{'CYCLE_START_TIME'} = time();
    return $sleep_time;
}

1;
