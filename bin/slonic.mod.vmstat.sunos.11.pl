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

my $KiToMi=1024;

my @vmstat_fields;
my $vmstat_page_opt="";

if (defined $CONF->{VMSTAT_PAGE} && $CONF->{VMSTAT_PAGE}==1)
{
    $vmstat_page_opt="-p";
    @vmstat_fields = (
        {name => 'vswap_MiB',      devider => $KiToMi, send2db => 1}, # col 1  memory swap 
        {name => 'free_MiB',       devider => $KiToMi, send2db => 1}, # col 2  memory free 
        {name => 'recl_MiB/s',     devider => $KiToMi, send2db => 1}, # col 3  page re 
        {name => 'mf_MiB/s',       devider => $KiToMi, send2db => 1}, # col 4  page mf 
        {name => 'fr_MiB/s',       devider => $KiToMi, send2db => 1}, # col 5  page fr 
        {name => 'def_MiB/s',      devider => $KiToMi, send2db => 1}, # col 6  page de 
        {name => 'scan_MiB/s',     devider => $KiToMi, send2db => 1}, # col 7  page sr 
        {name => 'epi_MiB/s',      devider => $KiToMi, send2db => 1}, # col 8  executable epi 
        {name => 'epo_MiB/s',      devider => $KiToMi, send2db => 1}, # col 9  executable epi 
        {name => 'epf_MiB/s',      devider => $KiToMi, send2db => 1}, # col 10 executable epf 
        {name => 'api_MiB/s',      devider => $KiToMi, send2db => 1}, # col 11 anonymous api 
        {name => 'apo_MiB/s',      devider => $KiToMi, send2db => 1}, # col 12 anonymous apo 
        {name => 'apf_MiB/s',      devider => $KiToMi, send2db => 1}, # col 13 anonymous apf 
        {name => 'fpi_MiB/s',      devider => $KiToMi, send2db => 1}, # col 14 filesystem fpi 
        {name => 'fpo_MiB/s',      devider => $KiToMi, send2db => 1}, # col 15 filesystem fpo 
        {name => 'fpf_MiB/s',      devider => $KiToMi, send2db => 1}, # col 16 filesystem fpf 
    );
}
else
{
    @vmstat_fields = (
        {name => 'RunQ',          devider => 1,       send2db => 1}, # col 1  kthr r 
        {name => 'BlockQ',        devider => 1,       send2db => 1}, # col 2  kthr b 
        {name => 'WaitQ',         devider => 1,       send2db => 1}, # col 3  kthr w 
        {name => 'vswap_MiB',      devider => $KiToMi, send2db => 1}, # col 4  memory swap 
        {name => 'free_MiB',       devider => $KiToMi, send2db => 1}, # col 5  memory free 
        {name => 'recl_MiB/s',     devider => $KiToMi, send2db => 1}, # col 6  page re 
        {name => 'mf_MiB/s',       devider => $KiToMi, send2db => 1}, # col 7  page mf 
        {name => 'pi_MiB/s',       devider => $KiToMi, send2db => 1}, # col 8  page pi 
        {name => 'po_MiB/s',       devider => $KiToMi, send2db => 1}, # col 9  page po 
        {name => 'fr_MiB/s',       devider => $KiToMi, send2db => 1}, # col 10 page fr 
        {name => 'def_MiB/s',      devider => $KiToMi, send2db => 1}, # col 11 page de 
        {name => 'scan_MiB/s',     devider => $KiToMi, send2db => 1}, # col 12 page sr 
        {name => 'd1_io/s',       devider => 1,       send2db => 0}, # col 13 disk [si]1 
        {name => 'd2_io/s',       devider => 1,       send2db => 0}, # col 14 disk [si]2 
        {name => 'd3_io/s',       devider => 1,       send2db => 0}, # col 15 disk [si]3 
        {name => 'd4_io/s',       devider => 1,       send2db => 0}, # col 16 disk [si]4 
        {name => 'inter/s',       devider => 1,       send2db => 1}, # col 17 faults in 
        {name => 'syscal/s',      devider => 1,       send2db => 1}, # col 18 faults sy 
        {name => 'csw/s',         devider => 1,       send2db => 1}, # col 19 faults cs 
        {name => 'user%',         devider => 1,       send2db => 1}, # col 20 cpu us 
        {name => 'sys%',          devider => 1,       send2db => 1}, # col 21 cpu sy 
        {name => 'idle%',         devider => 1,       send2db => 0}, # col 22 cpu id 
    );
}

my $outfilemgr=Slonic::LocalStorageMgr->new($CONF);

my $run=1;

my %vals ;
my $timestamp;

my $do_remote_send=check_remote_send($CONF);

while ($run)
{
    my $count=getruncount($CONF->{'PERIOD'}, $CONF->{'INTERVAL'}, $CONF->{'START_OFFSET'}, $CONF->{'START_TOLERANCE_INTERVAL'})+1;
    $outfilemgr->newfile($CONF->{LOCAL_STORAGE_FILENAME}."_".$CONF->{'INTERVAL'}."_".$count);
    my $CMD="/usr/bin/vmstat $vmstat_page_opt -T d $CONF->{'INTERVAL'} $count |";
    open (my $CMDOUT, $CMD) or die $log->fatal("Couldn't open $CMD for reading: $!");

    my $notfirstline=0;
    while (my $line=<$CMDOUT>) 
    {
        #Write raw line to local storage
        $outfilemgr->wtiteline(\$line);

        #End processing of current line if REMOTE_SEND in not true
        unless ($do_remote_send) { next };
 
        chomp $line;
        $line = trim($line);
        if ($line =~ '[0-9]+:[0-9]+:[0-9]+')
        {
            $timestamp = strdt2unix($line);
        }
        else
        {
            #printf("%s\n", $line);
            my @fields = split(/\s+/, $line);
            if ($fields[0] =~ '[0-9]+')
            {
                if ($notfirstline)
                {
                    my $nfields = scalar @fields;
                    for (my $i=0; $i<$nfields; $i++)
                    {
                        if ($vmstat_fields[$i]->{send2db})
                        {
                            # printf("%s: %d\n", $vmstat_colls[$i], $fields[$i]);
                            $vals{$vmstat_fields[$i]->{name}}=($vmstat_fields[$i]->{devider}!=1)?sprintf("%.2f",$fields[$i]/$vmstat_fields[$i]->{devider}):$fields[$i];
                        }
                    }
                    $channel->send([[$CONF->{MEASUREMENT_NAME}, \%vals, {}, $timestamp]]);
                    #print Dumper(\%vals);
                    #my $line4influx = data2line($CONF->{MEASUREMENT_NAME}, \%vals, \%mkeys, $timestamp);
                    #post data to pipe
                    #print $fh $line4influx."\n";
                }
                else 
                {
                    $notfirstline=1;
                }
            }
        }
    }
    close $CMDOUT;
}

exit(0);
