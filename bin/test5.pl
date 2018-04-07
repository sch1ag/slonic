#!/usr/bin/perl
use vars;
use strict;
use warnings;

use Data::Dumper;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Slonic::Utils qw(trim getruncount strdt2unix check_bins_fatal);

use Carp qw(croak);

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

#my $dlstat="/sbin/dlstat";
#my $dladm="/sbin/dladm";
#
#check_bins_fatal($dlstat, $dladm);
#
#my $up_net_dev=get_up_net_dev();
#until(%{$up_net_dev})
#{
#    $up_net_dev=get_up_net_dev();
#}
#
#print Dumper($up_net_dev);
#
#sub get_up_net_dev
#{
#    my %up_net_dev;
#    my $CMD="$dladm show-phys |";
#    open (my $cmdout, $CMD) or croak($log->fatal("Couldn't open $CMD for reading: $!"));
#
#    while (my $line=<$cmdout>)
#    {
#        chomp $line;
#        print "$line\n";
#        if (my ($linkname, $mediatype, $linkstate, $linkspeed, $linkduplex, $devname) = ($line=~/(\w+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\w+)\s+(\w+)/))
#        {
#            print("$linkname, $mediatype, $linkstate, $linkspeed, $linkduplex, $devname\n");
#            if ($linkstate eq "up")
#            {
#                $up_net_dev{$linkname}={'linkname'=>$linkname, 'mediatype'=>$mediatype, 'linkspeed'=>$linkspeed, 'devname'=>$devname};
#            }
#        }
#    }
#    return \%up_net_dev;
#}



#my @true=('^[Oo][Nn]$', '^[Tr][Rr][Uu][Ee]$', '^[Yy][Ee][Ss]$', '^[1-9]+$');
#if (grep($var =~ /$_/i, @true))
#{
#
#}

for my $v (qw(on On ON oN True true TrUe tRuE yes YES YeS yEs 1 2 3 4 Yes1 true2 0 oij wd oi off false))
{
    print "T $v : ".check_true($v)."\n";
    print "F $v : ".check_false($v)."\n";
}

sub check_true
{
    my $var=shift;
    if ($var=~/^(on|true|yes|1)$/i)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub check_false
{
    my $var=shift;
    if ($var=~/^(off|false|no|0)$/i)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

