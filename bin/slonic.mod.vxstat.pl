#!/usr/bin/perl
use vars;
use strict;
use warnings;

our $VERSION = '1.0.1';

use File::Basename;
use IO::Handle;
use Getopt::Std;
use POSIX qw(strftime);
use Data::Dumper;
use List::Util qw(max);
#require 5.6.0;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Slonic::Utils qw(trim select_abs_path getruncount strdt2unix check_remote_send);
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

my $run=1;

my %vals ;
my $timestamp;

#check that VxVM installed and commands available for execution.
my $vxstat="/usr/sbin/vxstat";

for my $vxcmd ($vxstat)
{
    if (-e $vxcmd)
    {
        unless (-x $vxcmd)
        {
            croak($log->fatal("$vxcmd is not executable by current userid. Exiting."));
        }
    }
    else
    {
        croak($log->notice("Seems VxVM is not installed. Could not find binary $vxcmd. Exiting."));
    }
}

#check that vx device dir is exist
my $dgdevdir="/dev/vx/dsk";
unless (-d $dgdevdir)
{
    croak($log->notice("Looks like VxVM is not configured on this host. Exiting."));
}

my $objopt=join("", "-", map(substr($_,0,1), @{$CONF->{'VXOBJECTS'}}));

my $do_remote_send=check_remote_send($CONF);

while ($run)
{
    #check for imported DGs
    opendir(my $dh, $dgdevdir) || croak $log->fatal("Could not opendir $dgdevdir to check imported DGs: $!");
    my @dirents = readdir($dh);
    closedir $dh;

    #dgs is imported if numbers of entitys is more than 2 (not only . and ..)
    until (scalar @dirents>2)
    {
        $log->debug("No vx disk droups imported yet. Will check every $CONF->{'DG_IMPORTED_CHECK_INTERVAL'} seconds.");
        sleep $CONF->{'DG_IMPORTED_CHECK_INTERVAL'};
        opendir(my $dh, $dgdevdir) || croak $log->fatal("Can opendir $dgdevdir to check imported DGs: $!");
        @dirents = readdir($dh);
        closedir $dh;
    }

    my $count=getruncount($CONF->{'PERIOD'}, $CONF->{'INTERVAL'}, $CONF->{'START_OFFSET'}, $CONF->{'START_TOLERANCE_INTERVAL'});
    $outfilemgr->newfile($CONF->{LOCAL_STORAGE_FILENAME}."_".$CONF->{'INTERVAL'}."_".$count);
    my $CMD="$vxstat -o alldgs $objopt -u k -i $CONF->{'INTERVAL'} -c $count -S |";
    open (my $CMDOUT, $CMD) or croak($log->fatal("Couldn't open $CMD for reading: $!"));

    my $snapnumber=0;
    my $dgname="";
    my $blankline=0;

    my $data_href={};
    my $data2send=[];

    while (my $line=<$CMDOUT>) 
    {
        #Write raw line to local storage
        $outfilemgr->wtiteline(\$line);

        #End processing of current line if REMOTE_SEND in not true
        unless ($do_remote_send) { next };

        chomp $line;

        if(my ($objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms) = ($line=~/^(dm|sd|pl|vol)\s+([\w\.\-]+)\s+(\d+)\s+(\d+)\s+(\d+)k\s+(\d+)k\s+(\d+\.\d+)\s+(\d+\.\d+)/))
        {
            #save data of the line if current snapshot is not the first (historical) output of vxstat 
            #data of the line also will be skipped in case of unbelievable high iops (strange vxstat behavior during dg deport)
            if($snapnumber>1 && $read_iops <= $CONF->{'MAX_POSSIBLE_IOPS'} && $write_iops <= $CONF->{'MAX_POSSIBLE_IOPS'})
            {
                #store data for aggregations
                storefields($data_href, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms);
                
                #save per object data if it is defined in config 
                if ($CONF->{'POST_OBJECTS_STAT'} == 1 || $dgname =~ $CONF->{'POST_OBJECTS_STAT_DG_RE'} || $objname =~ $CONF->{'POST_OBJECTS_STAT_OBJ_RE'})
                {
                    my $aggrgrp="object";
                    add_data2send($data2send, $timestamp, $aggrgrp, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms, $read_srv_ms, $write_srv_ms);
                }
            }
            $blankline=0;
        }
        elsif ($line =~ /^DG\s+([\w\.\-]+)/)
        {
            $dgname = $1;
            $blankline=0;
        }
        elsif ($line =~ /(\d\d):(\d\d):(\d\d)/)
        {
            $timestamp = strdt2unix($line);
            $snapnumber++;
            $blankline=0;
        }
        elsif ($line =~ /^$/)
        {
            #print("Empty line\n");
            if($blankline==1) #previous line was blank too
            {
                #print("Second empty line\n");
                $blankline=0;
                #postprocess and post data
                calc_and_add_aggr_data($data_href, $timestamp, $data2send);
                $channel->send($data2send);
                
                $data_href={};
                $data2send=[];
            }
            else
            {
                $blankline=1;
            }
        }
    }
    close $CMDOUT;
}

sub add_data2send
{
    my ($data2send_aref, $timestamp, $aggrgrp, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms, $max_read_srv_ms, $max_write_srv_ms) = @_;

    my %tags;
    $tags{$CONF->{'VXAGGRGRP_KEYNAME'}}=$aggrgrp;
    $tags{'dgname'}=$dgname;
    $tags{'objtype'}=$objtype;
    $tags{'objname'}=$objname;

    my $KiToMi=1024;
    my %vals;

    $vals{'read_io/s'}=sprintf("%d", $read_iops);
    $vals{'write_io/s'}=sprintf("%d", $write_iops);

    $vals{'read_MiB/s'}=sprintf("%.3f", $read_kbps/$KiToMi);
    $vals{'write_MiB/s'}=sprintf("%.3f", $write_kbps/$KiToMi);

    $vals{'read_io_asize_MiB'}=($read_iops!=0)?sprintf("%.3f", $read_kbps/$read_iops/$KiToMi):"0.0";
    $vals{'write_io_asize_MiB'}=($write_iops!=0)?sprintf("%.3f", $write_kbps/$write_iops/$KiToMi):"0.0";

    $vals{'read_atime_ms'}=sprintf("%.2f", $read_srv_ms);
    $vals{'write_atime_ms'}=sprintf("%.2f", $write_srv_ms);

    $vals{'read_atime_max_ms'}=sprintf("%.2f", $max_read_srv_ms);
    $vals{'write_atime_max_ms'}=sprintf("%.2f", $max_write_srv_ms);

    push(@{$data2send_aref}, [$CONF->{MEASUREMENT_NAME}, \%vals, \%tags, $timestamp]);
}

sub storefields
{
    my ($data_href, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms) = @_;

    #printf("$dgname $objtype $objname $read_iops $write_iops $read_kbps $write_kbps $read_srv_ms $write_srv_ms\n");

    for my $agrp (keys %{$CONF->{'VXAGGRGRPS'}})
    {
        if ($objtype eq $CONF->{'VXAGGRGRPS'}->{$agrp}->{'OBJTYPE'} 
            && $dgname =~ $CONF->{'VXAGGRGRPS'}->{$agrp}->{'DGNAME'}
            && $objname =~ $CONF->{'VXAGGRGRPS'}->{$agrp}->{'OBJNAME'})
        {
            $data_href->{$agrp}->{$objtype}->{'pattern'}->{'pattern'}=calc_intermed_aggr_values($data_href->{$agrp}->{$objtype}->{'pattern'}->{'pattern'}, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms);
        }
    }

    if (grep($objtype eq $_, @{$CONF->{'VXOBJECTS'}}))
    {
        $data_href->{'aggrbydg'}->{$objtype}->{$dgname}->{'all'}=calc_intermed_aggr_values($data_href->{'aggrbydg'}->{$objtype}->{$dgname}->{'all'}, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms);
    
        $data_href->{'aggrall'}->{$objtype}->{'all'}->{'all'}=calc_intermed_aggr_values($data_href->{'aggrall'}->{$objtype}->{'all'}->{'all'}, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms);
    }
    #print Dumper($data_href);
}

sub calc_intermed_aggr_values
{
    my ($intermed_data, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms)=@_;
    if (ref($intermed_data) ne 'HASH')
    {
        $intermed_data={};
        $intermed_data->{'Sum.RIOpS'}=$read_iops;
        $intermed_data->{'Sum.WIOpS'}=$write_iops;

        $intermed_data->{'Sum.RKBpS'}=$read_kbps;
        $intermed_data->{'Sum.WKBpS'}=$write_kbps;
        
        $intermed_data->{'Tmp.RSRVxRIOpS'}=$read_iops*$read_srv_ms;
        $intermed_data->{'Tmp.WSRVxWIOpS'}=$write_iops*$write_srv_ms;

        $intermed_data->{'Max.RSRV'}=$read_srv_ms;
        $intermed_data->{'Max.WSRV'}=$write_srv_ms;
    }
    else
    {
        $intermed_data->{'Sum.RIOpS'}+=$read_iops;
        $intermed_data->{'Sum.WIOpS'}+=$write_iops;
        
        $intermed_data->{'Sum.RKBpS'}+=$read_kbps;
        $intermed_data->{'Sum.WKBpS'}+=$write_kbps;
        
        $intermed_data->{'Tmp.RSRVxRIOpS'}+=$read_iops*$read_srv_ms;
        $intermed_data->{'Tmp.WSRVxWIOpS'}+=$write_iops*$write_srv_ms;
        
        $intermed_data->{'Max.RSRV'}=max($intermed_data->{'Max.RSRV'}, $read_srv_ms);
        $intermed_data->{'Max.WSRV'}=max($intermed_data->{'Max.WSRV'}, $write_srv_ms);
    }
    
    return $intermed_data;
}

sub calc_and_add_aggr_data
{
    my ($data_href, $timestamp, $data2send_aref)=@_;

    my ($data, $aggrgrp, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms, $max_read_srv_ms, $max_write_srv_ms);
    
    for $aggrgrp (keys %{$data_href})
    {
        for $objtype (keys %{$data_href->{$aggrgrp}})
        {
            for $dgname (keys %{$data_href->{$aggrgrp}->{$objtype}})
            {
                for $objname (keys %{$data_href->{$aggrgrp}->{$objtype}->{$dgname}})
                {
                    $data=$data_href->{$aggrgrp}->{$objtype}->{$dgname}->{$objname};
                    $read_iops=$data->{'Sum.RIOpS'};
                    $write_iops=$data->{'Sum.WIOpS'};
                    $read_kbps=$data->{'Sum.RKBpS'};
                    $write_kbps=$data->{'Sum.WKBpS'};
                    $read_srv_ms=($data->{'Sum.RIOpS'}!=0)?$data->{'Tmp.RSRVxRIOpS'}/$data->{'Sum.RIOpS'}:0;
                    $write_srv_ms=($data->{'Sum.WIOpS'}!=0)?$data->{'Tmp.WSRVxWIOpS'}/$data->{'Sum.WIOpS'}:0; 
                    $max_read_srv_ms=$data->{'Max.RSRV'};
                    $max_write_srv_ms=$data->{'Max.WSRV'};
                    add_data2send($data2send_aref, $timestamp, $aggrgrp, $dgname, $objtype, $objname, $read_iops, $write_iops, $read_kbps, $write_kbps, $read_srv_ms, $write_srv_ms, $max_read_srv_ms, $max_write_srv_ms);
                }
            }
        }
    } 

}

exit(0);

