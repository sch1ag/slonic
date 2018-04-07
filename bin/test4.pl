#!/usr/bin/perl -w
# SimpLe ONline Information Collector: test program
# VYKostornoy@sberbank.ru
# Version 0.1

use vars;
use strict;
use warnings;

use Data::Dumper;
use FindBin qw($Bin $Script);
use lib "$Bin/../lib";
use Slonic::Utils qw( get_config );
use Proc::Background;
use Proc::Daemon;
use POSIX;

use Carp qw(croak);
use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

croak $log->fatal("Ouh");

print Dumper(\%ENV."\n\n\n\n\n\n");
print "$$\n"; 
print "$Script\n";

    #check for SLONIC_HOME env variable
    if (defined $ENV{"SLONIC_HOME"})
    {
        print "$ENV{'SLONIC_HOME'}\n";
    };

Proc::Daemon::Init;
POSIX::setsid();

for (my $i=0; $i<=5; $i++)
{
    my $command = "sleep ".(100+$i);
    my $proc1 = Proc::Background->new($command);
}

sleep 600 ;
