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
use Slonic::Config;

my $conf=get_config("general.netd");
#my $conf=get_config("general.mod.vmstat", "/etc/opt/slonic/slonic.cf");



print Dumper($conf);

my $exchange = Slonic::Buff2Net->new({filename=>"/tmp/testfile.txt"});
#    my ($class, $filename, $nonblocklock, $lockretry, $waittime) = @_;

my @somedata = (1, 2, 3, 4, 5, 6, 7, 8, 9, 0);
print Dumper(@somedata);
my $nrows = $exchange->append(@somedata);
print "rows $nrows\n";
