package Slonic::ElementDispenser;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Carp qw(croak);
use Log::Any qw($log);

sub new {
    my ($class, $params_ref) = @_;
    my $self = {};

    #Expected: portion, recipient

    unless (defined $params_ref->{'recipient'} && ref $params_ref->{'recipient'} eq 'CODE')
    {
        croak $log->fatal("recipient must be defined as sub reference");
    }

    $self->{'recipient'} = $params_ref->{'recipient'};

    unless (defined $params_ref->{'portion'} && $params_ref->{'portion'} =~ /^\d+$/)
    {   
        croak $log->fatal("portion must be defined as numeric value");
    }

    $self->{'portion'} = $params_ref->{'portion'};

    $self->{'databuffer'} = [];
    
    bless($self, $class);
    return $self;
}

sub add_elements
{
    my ($self, $newdataref) = @_;
    while (@{$newdataref})
    {
        push @{$self->{'databuffer'}}, shift @{$newdataref};
        if (@{$self->{'databuffer'}} >= $self->{'portion'})
        {
            $self->flush_buffer();
        }
    }
}

sub flush_buffer
{
    my $self = shift;
    $self->{'recipient'}->($self->{'databuffer'});
    $self->{'databuffer'} = [];
}

1;
