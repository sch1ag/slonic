#!/usr/bin/perl -w
# SimpLe ONline Information Collector: test program
# VYKostornoy@sberbank.ru
# Version 0.1

use vars;
use strict;
use warnings;

use Data::Dumper;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Slonic::Utils qw( get_config );
use Slonic::Buff2Net;
use Time::HiRes qw( time );


my $conf=get_config("general.netd");
print Dumper($conf);


my $INTERVAL=1;
my $PERIOD=3600;
my $OFFSET=600;

sub getruncount{
    my ($PERIOD, $INTERVAL, $OFFSET) = @_;
    my $normoffset=$OFFSET % $PERIOD;
    my $currtime=sprintf("%d", time());
    my $rest=$currtime % $PERIOD;

    my $nextstart=$currtime-$rest+$normoffset;
    $nextstart+=$PERIOD if ($nextstart<=$currtime);

    my $timetorun = $nextstart - $currtime;
    return sprintf("%d", $timetorun/$INTERVAL);
print "currtime   ".$currtime."\n";
print "normoffset ".$normoffset."\n";
print "rest       ".$rest."\n";
print "nextstart  ".$nextstart."\n";
}

print "count      ".getruncount($PERIOD, $INTERVAL, $OFFSET)."\n";

