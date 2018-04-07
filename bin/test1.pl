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

print Dumper(\%ENV."\n\n\n\n\n\n");
print "$$\n"; 
print "$Script\n";

my @ENV_TAG_KEYS = grep { $_ =~ /^SLONIC_TAG_/ } keys %ENV;
my %ENV_TAGS = map {substr($_, 11) => $ENV{$_}} @ENV_TAG_KEYS;
print Dumper(\%ENV_TAGS);

sleep 100;

exit(0);

my %a=('a' => 'b', 'c1' => 1); 
my %b=('c' => 'd');
my %c = (%a, %b);

print Dumper(\%c);

#join(', ', map { "'$_' => \"${a{$_}}\"" } keys %a), "\n";"

exit(0);
