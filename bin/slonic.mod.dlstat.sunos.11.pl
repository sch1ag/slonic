#!/usr/bin/perl
use vars;
use strict;
use warnings;

our $VERSION = '1.0.2';

use File::Basename;
use IO::Handle;
use Getopt::Std;
use POSIX qw(strftime);
use Data::Dumper;
use List::Util qw(max);
#require 5.6.0;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Slonic::Utils qw(trim select_abs_path getruncount strdt2unix check_bins_fatal check_remote_send);
use Slonic::LocalStorageMgr;
use Slonic::M2DChannel;
use Slonic::Config;
use Carp qw(croak);

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

$ENV{"LC_TIME"}="C";

my $CFGNAME = $ARGV[0]; 
my $CFGOBJ = Slonic::Config->new($CFGNAME);
my $CONF = $CFGOBJ->{CONF};

my $channel=Slonic::M2DChannel->new($CONF);

my $outfilemgr = Slonic::LocalStorageMgr->new($CONF);

my %vals;
my $timestamp;

my $do_remote_send=check_remote_send($CONF);

#check that commands exists and available for execution
my $dlstat="/sbin/dlstat";
my $dladm="/sbin/dladm";

#check for NETOBJECT option 
my @possible_objcs=("link", "phys");
unless (grep($_ eq $CONF->{'NETOBJECT'}, @possible_objcs))
{
    croak($log->fatal("NETOBJECT parameter must be ".join(" or ", @possible_objcs)." But it is $CONF->{'NETOBJECT'}"));
}

check_bins_fatal($dlstat, $dladm);

my $up_net_dev;
my $BToMiB=1048576;

my $run=1;
while ($run)
{
    $up_net_dev=get_up_net_dev();
    until(%{$up_net_dev})
    {
        $log->debug("No UP network interfaces forund. Will check every $CONF->{'NET_UP_CHECK_INTERVAL'} seconds.");
        sleep $CONF->{'NET_UP_CHECK_INTERVAL'};
        $up_net_dev=get_up_net_dev();
    }

    my $count=getruncount($CONF->{'PERIOD'}, $CONF->{'INTERVAL'}, $CONF->{'START_OFFSET'}, $CONF->{'START_TOLERANCE_INTERVAL'})+1;
    $outfilemgr->newfile($CONF->{LOCAL_STORAGE_FILENAME}."_show-".$CONF->{'NETOBJECT'}."_".$CONF->{'INTERVAL'}."_".$count);
    my $CMD="$dlstat show-$CONF->{'NETOBJECT'} -u R -T d $CONF->{'INTERVAL'} $count |";
    open (my $CMDOUT, $CMD) or croak($log->fatal("Could not open $CMD for reading: $!"));

    my $snapnumber=0;
    my @data2send;

    while (my $line=<$CMDOUT>) 
    {
        #Write raw line to local storage
        $outfilemgr->wtiteline(\$line);

        #End processing of current line if REMOTE_SEND in not true
        unless ($do_remote_send) { next };

        chomp $line;

        if(my ($linkname, $in_pkts_per_sec, $in_bytes_per_sec, $out_pkts_per_sec, $out_bytes_per_sec)=($line=~/^\s*([\w\-\.]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/))
        {
            #printf("$line\n");
            if($snapnumber>1)
            {
                for my $uplinkname (keys %{$up_net_dev})
                {
                    if($uplinkname eq $linkname)
                    {
                        my $vals={};
                        $vals->{'in_packets/s'}=sprintf("%d", $in_pkts_per_sec);
                        $vals->{'out_packets/s'}=sprintf("%d", $out_pkts_per_sec);
                        $vals->{'in_MiB/s'}=sprintf("%.6f", $in_bytes_per_sec/$BToMiB);
                        $vals->{'out_MiB/s'}=sprintf("%.6f", $out_bytes_per_sec/$BToMiB);

                        $vals->{'in_pkt_asize_MiB'}=($in_pkts_per_sec!=0)?sprintf("%.6f", $in_bytes_per_sec/$in_pkts_per_sec/$BToMiB):"0.0";
                        $vals->{'out_pkt_asize_MiB'}=($out_pkts_per_sec!=0)?sprintf("%.6f", $out_bytes_per_sec/$out_pkts_per_sec/$BToMiB):"0.0";
                        
                        if(defined $up_net_dev->{$uplinkname}->{'linkspeed'})
                        {
                            $vals->{'link_speed_MiB/s'}=sprintf("%d", $up_net_dev->{$uplinkname}->{'linkspeed'}/8);
                        }

                        my $keys={};
                        $keys->{'link'}=$linkname;
                        $keys->{'object'}=$CONF->{'NETOBJECT'};
                        
                        push(@data2send, [$CONF->{MEASUREMENT_NAME}, $vals, $keys, $timestamp]);
                    }
                }
            }
        }
        elsif ($line =~ /(\d\d):(\d\d):(\d\d)/)
        {
            $timestamp = strdt2unix($line);
            if($snapnumber>1)
            {
                $channel->send(\@data2send);
                @data2send=();
            }
            $snapnumber++;
        }
    }
    close $CMDOUT;
}

sub get_up_net_dev
{
    my %up_net_dev;
    my $CMD="$dladm show-$CONF->{'NETOBJECT'} |";
    open (my $CMDOUT, $CMD) or croak($log->fatal("Couldn't open $CMD for reading: $!"));

    while (my $line=<$CMDOUT>)
    {
        chomp $line;

        my ($linkname, $mediatype, $linkstate, $linkspeed, $linkduplex, $devname,$class, $mtu, $over);
        if (($linkname, $mediatype, $linkstate, $linkspeed, $linkduplex, $devname) = ($line=~/^([\w\-\.]+)\s+([\w\-\.]+)\s+([\w\-\.]+)\s+(\d+)\s+([\w\-\.]+)\s+([\w\-\.]+)/))
        {
            if ($linkstate eq "up")
            {
                $up_net_dev{$linkname}={'linkname'=>$linkname, 'mediatype'=>$mediatype, 'linkspeed'=>$linkspeed, 'devname'=>$devname};
            }
        }
        elsif (($linkname, $class, $mtu, $linkstate, $over) = ($line=~/^([\w\-\.]+)\s+([\w\-\.]+)\s+(\d+)\s+([\w\-\.]+)\s+([\w\-\.]+)\s*$/))
        {
            if ($linkstate eq "up")
            {
                $up_net_dev{$linkname}={'linkname'=>$linkname, 'class'=>$class, 'mtu'=>$mtu, 'over'=>$over};
            }
        }
    }
    close $CMDOUT;
    return \%up_net_dev;
}


exit(0);

