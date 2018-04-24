#!/usr/bin/perl
use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

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

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

$ENV{"LC_TIME"}="C";

my $CFGNAME = $ARGV[0]; 
my $CFGOBJ = Slonic::Config->new($CFGNAME);
my $CONF = $CFGOBJ->{CONF};

my $channel=Slonic::M2DChannel->new($CONF);

my %name2colon = (
    'RIOpS'=>0,       # col 1  r/s
    'WIOpS'=>1,       # col 2  w/s
    'RKBpS'=>2,       # col 3  kr/s
    'WKBpS'=>3,       # col 4  kw/s
    'WAITQUEUE'=>4,   # col 5  wait
    'SRVQUEUE'=>5,    # col 6  actv
    'WAITTIME'=>6,    # col 7  wsvc_t
    'SRVTIME'=>7,     # col 8  asvc_t
    'WAITnoEMPTY'=>8, # col 9  %w
    'SRVnoEMPTY'=>9,  # col 10 %b
    'DEVICE'=>10,     # col 11 device
);

my $outfilemgr = Slonic::LocalStorageMgr->new($CONF);

my $run=1;

my %vals ;
my $timestamp;

my $do_remote_send=check_remote_send($CONF);

while ($run){
    my $count=getruncount($CONF->{'PERIOD'}, $CONF->{'INTERVAL'}, $CONF->{'START_OFFSET'}, $CONF->{'START_TOLERANCE_INTERVAL'})+1; 
    $outfilemgr->newfile($CONF->{LOCAL_STORAGE_FILENAME}."_".$CONF->{'INTERVAL'}."_".$count);
    my $CMD="/usr/bin/iostat -T d -nxdC $CONF->{'INTERVAL'} $count |";
    open (my $CMDOUT, $CMD) or die $log->fatal("Couldn't open $CMD for reading: $!");

    my $skip_report_on_timeline=2;
    my $curdev="";
    my $lastdev="";
    my $interval_reported=0;
    my %databygrp;

    while (my $line=<$CMDOUT>) 
    {
        #Write raw line to local storage
        $outfilemgr->wtiteline(\$line);

        #End processing of current line if REMOTE_SEND in not true
        unless ($do_remote_send) { next };

        chomp $line;
        $line = trim($line);
        my @fields = split(/\s+/, $line);

        if ($line =~ '[0-9]+:[0-9]+:[0-9]+'){ #time line
            #print "DEBUG: $line\n";
            if ($skip_report_on_timeline==0){
                #next condition may be true if devices have changed during stat command is running
                if ($interval_reported==0){
                    do_report(\%databygrp, $timestamp, $channel);
                }
            } 
            else {
                $skip_report_on_timeline--;
            }
            $lastdev=$curdev;
	    $timestamp=strdt2unix($line);
            %databygrp=();
	}
        elsif(scalar @fields == 11 && $fields[0] =~ '[0-9\.]+') #data line
        {
            $curdev=$fields[$name2colon{'DEVICE'}];
	    if ($curdev =~ '^c[0-9]+$'){ #stats by controller (hardcoded)
                #my $grpname=$curdev;
                storefields($curdev, \@fields, \%databygrp);
            }
            for my $grpname (keys %{$CONF->{IOAGGRGRP}}){
                my $grpregx=$CONF->{IOAGGRGRP}->{$grpname};
                if ($curdev =~ $grpregx){
                    #do processing
                    #print "DEBUG: $line\n";
                    storefields($grpname, \@fields, \%databygrp);
                }
            }
           
            if($curdev eq $lastdev){
                if ($skip_report_on_timeline==0){ 
                   do_report(\%databygrp, $timestamp, $channel);
                   $interval_reported=1;
                }
            }
	}
    }
    close $CMDOUT;
}

exit(0);

sub do_report {
    my $dataref = shift;
    my $timestamp = shift;
    my $channel = shift;
    my @data2send;

    my $KiToMi=1024;

    for my $grpname (keys %{$dataref}){
        my %tags;

        $tags{$CONF->{'IOAGGRGRP_KEYNAME'}}=$grpname;

        my $grpdataref=$dataref->{$grpname};
        my %vals;
        $vals{'read_io/s'}=sprintf("%.1f", $grpdataref->{'Sum.RIOpS'});
        $vals{'write_io/s'}=sprintf("%.1f",$grpdataref->{'Sum.WIOpS'});

        $vals{'read_MiB/s'}=sprintf("%.3f", $grpdataref->{'Sum.RKBpS'}/$KiToMi);
        $vals{'write_MiB/s'}=sprintf("%.3f", $grpdataref->{'Sum.WKBpS'}/$KiToMi);

        $vals{'read_io_asize_MiB'}=($grpdataref->{'Sum.RIOpS'}!=0)?sprintf("%.4f", $grpdataref->{'Sum.RKBpS'}/$grpdataref->{'Sum.RIOpS'}/$KiToMi):"0.0";
        $vals{'write_io_asize_MiB'}=($grpdataref->{'Sum.WIOpS'}!=0)?sprintf("%.4f", $grpdataref->{'Sum.WKBpS'}/$grpdataref->{'Sum.WIOpS'}/$KiToMi):"0.0";

        $vals{'wait_queue_sum'}=sprintf("%.1f", $grpdataref->{'Sum.WAITQUEUE'});
        $vals{'svc_queue_sum'}=sprintf("%.1f", $grpdataref->{'Sum.SRVQUEUE'});

        $vals{'wait_atime_max_ms'}=sprintf("%.1f", $grpdataref->{'Max.WAITTIME'});
        $vals{'svc_atime_max_ms'}=sprintf("%.1f", $grpdataref->{'Max.SRVTIME'});
        $vals{'total_atime_max_ms'}=sprintf("%.1f", $grpdataref->{'Max.TOTALTIME'});

        my $totalIOpS=$grpdataref->{'Sum.RIOpS'}+$grpdataref->{'Sum.WIOpS'};
        $vals{'wait_atime_ms'}=($totalIOpS!=0)?sprintf("%.2f", $grpdataref->{'Tmp.WAITTIMExTIOpS'}/$totalIOpS):"0.0";
        $vals{'svc_atime_ms'}=($totalIOpS!=0)?sprintf("%.2f", $grpdataref->{'Tmp.SRVTIMExTIOpS'}/$totalIOpS):"0.0";
        $vals{'total_atime_ms'}=sprintf("%.2f", $vals{'wait_atime_ms'}+$vals{'svc_atime_ms'});

        $vals{'wait_wavg_%'}=($grpdataref->{'Tmp.WAITnoEMPTY_devs'}!=0)?sprintf("%.2f", $grpdataref->{'Sum.WAITnoEMPTY'}/$grpdataref->{'Tmp.WAITnoEMPTY_devs'}):"0.0";
        $vals{'busy_wavg_%'}=($grpdataref->{'Tmp.SRVnoEMPTY_devs'}!=0)?sprintf("%.2f", $grpdataref->{'Sum.SRVnoEMPTY'}/$grpdataref->{'Tmp.SRVnoEMPTY_devs'}):"0.0";

        $vals{'wait_max_%'}=sprintf("%.2f", $grpdataref->{'Max.WAITnoEMPTY'});
        $vals{'busy_max_%'}=sprintf("%.2f", $grpdataref->{'Max.SRVnoEMPTY'});

        #print "DEBUG: GRP $grpname\n";
        push(@data2send, [$CONF->{MEASUREMENT_NAME}, \%vals, \%tags, $timestamp]);
    }
    $channel->send(\@data2send);
};

sub storefields {
    my $grpname = shift;
    my $in_fieldsref = shift;
    my $out_hashref = shift;
    #print "DEBUG: $grpname\n";
    unless (exists $out_hashref->{$grpname}) {
        my %storetemplate = (
            'Tmp.NUMBERofDEVs'=>0,
            'Sum.RIOpS'=>0,
            'Sum.WIOpS'=>0,
            'Sum.RKBpS'=>0,
            'Sum.WKBpS'=>0,
            'Sum.WAITQUEUE'=>0,
            'Sum.SRVQUEUE'=>0,

            'Tmp.WAITTIMExTIOpS'=>0,
            'Tmp.SRVTIMExTIOpS'=>0,

            'Tmp.WAITnoEMPTY_devs'=>0,
            'Tmp.SRVnoEMPTY_devs'=>0,

            'Sum.WAITnoEMPTY'=>0,
            'Sum.SRVnoEMPTY'=>0,
            'Max.WAITnoEMPTY'=>0,
            'Max.SRVnoEMPTY'=>0,

            'Max.WAITTIME'=>0,
            'Max.SRVTIME'=>0,
            'Max.TOTALTIME'=>0,
        );

        $out_hashref->{$grpname} = \%storetemplate;
    } 

    $out_hashref->{$grpname}->{'Tmp.NUMBERofDEVs'}++;

    $out_hashref->{$grpname}->{'Sum.RIOpS'}+=$in_fieldsref->[$name2colon{'RIOpS'}];
    $out_hashref->{$grpname}->{'Sum.WIOpS'}+=$in_fieldsref->[$name2colon{'WIOpS'}];

    $out_hashref->{$grpname}->{'Sum.RKBpS'}+=$in_fieldsref->[$name2colon{'RKBpS'}];
    $out_hashref->{$grpname}->{'Sum.WKBpS'}+=$in_fieldsref->[$name2colon{'WKBpS'}];

    $out_hashref->{$grpname}->{'Sum.WAITQUEUE'}+=$in_fieldsref->[$name2colon{'WAITQUEUE'}];
    $out_hashref->{$grpname}->{'Sum.SRVQUEUE'}+=$in_fieldsref->[$name2colon{'SRVQUEUE'}];

    my $curTIOpS=$in_fieldsref->[$name2colon{'RIOpS'}]+$in_fieldsref->[$name2colon{'WIOpS'}];
    $out_hashref->{$grpname}->{'Tmp.WAITTIMExTIOpS'}+=$in_fieldsref->[$name2colon{'WAITTIME'}]*$curTIOpS;
    $out_hashref->{$grpname}->{'Tmp.SRVTIMExTIOpS'}+=$in_fieldsref->[$name2colon{'SRVTIME'}]*$curTIOpS;

    $out_hashref->{$grpname}->{'Max.WAITTIME'}=max($in_fieldsref->[$name2colon{'WAITTIME'}], $out_hashref->{$grpname}->{'Max.WAITTIME'});
    $out_hashref->{$grpname}->{'Max.SRVTIME'}=max($in_fieldsref->[$name2colon{'SRVTIME'}], $out_hashref->{$grpname}->{'Max.SRVTIME'});

    my $curTOTALTIME=$in_fieldsref->[$name2colon{'WAITTIME'}]+$in_fieldsref->[$name2colon{'SRVTIME'}];
    $out_hashref->{$grpname}->{'Max.TOTALTIME'}=max($curTOTALTIME, $out_hashref->{$grpname}->{'Max.TOTALTIME'});
  
    if ($in_fieldsref->[$name2colon{'WAITnoEMPTY'}]>0){
        $out_hashref->{$grpname}->{'Tmp.WAITnoEMPTY_devs'}++;
        $out_hashref->{$grpname}->{'Sum.WAITnoEMPTY'}+=$in_fieldsref->[$name2colon{'WAITnoEMPTY'}];
        $out_hashref->{$grpname}->{'Max.WAITnoEMPTY'}=max($in_fieldsref->[$name2colon{'WAITnoEMPTY'}], $out_hashref->{$grpname}->{'Max.WAITnoEMPTY'});
    }
    if ($in_fieldsref->[$name2colon{'SRVnoEMPTY'}]>0){
        $out_hashref->{$grpname}->{'Tmp.SRVnoEMPTY_devs'}++;
        $out_hashref->{$grpname}->{'Sum.SRVnoEMPTY'}+=$in_fieldsref->[$name2colon{'SRVnoEMPTY'}];
        $out_hashref->{$grpname}->{'Max.SRVnoEMPTY'}=max($in_fieldsref->[$name2colon{'SRVnoEMPTY'}], $out_hashref->{$grpname}->{'Max.SRVnoEMPTY'});
    }
}

