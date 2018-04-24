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
use Time::Local;

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

$ENV{"LC_TIME"}="C";

my $CFGNAME = $ARGV[0]; 
my $CFGOBJ = Slonic::Config->new($CFGNAME);
my $CONF = $CFGOBJ->{CONF};

my $channel=Slonic::M2DChannel->new($CONF);

my $outfilemgr=Slonic::LocalStorageMgr->new($CONF);

my $run=1;

my %vals ;
my $timestamp;

my @fields;

my $do_remote_send=check_remote_send($CONF);

while ($run)
{
    my $count=getruncount($CONF->{'PERIOD'}, $CONF->{'INTERVAL'}, $CONF->{'START_OFFSET'}, $CONF->{'START_TOLERANCE_INTERVAL'});
    $outfilemgr->newfile($CONF->{'LOCAL_STORAGE_FILENAME'}."_".$CONF->{'INTERVAL'}."_".$count);
    my $CMD="/usr/bin/sar -mvc $CONF->{'INTERVAL'} $count |";
    open (my $CMDOUT, $CMD) or die $log->fatal("Couldn't open $CMD for reading: $!");

    my $day_href = {};
    my $prevhours = 0;
    my $data_href = {};

    while (my $line=<$CMDOUT>) 
    {
        #Write raw line to local storage
        $outfilemgr->wtiteline(\$line);

        #End processing of current line if REMOTE_SEND in not true
        unless ($do_remote_send) { next };
 
        chomp $line;
        $line = trim($line);

        #HH:mm:ss   msg/s  sema/s
        #           proc-sz    ov  inod-sz    ov  file-sz    ov   lock-sz
        #           scall/s sread/s swrit/s  fork/s  exec/s rchar/s wchar/s
        #
        #22:19:48   0.00      0.00
        #           89/30000     0    0/129797       0  515/515       0     0/0   
        #           2629        17          32    0.00     0.00    3860    5794

        if (my ($scall, $sread, $swrit, $fork, $exec, $rchar, $wchar) = ($line =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+)\s+(\d+)\s*/))
        {
            $data_href->{'scall/s'} = $scall;
            $data_href->{'sread/s'} = $sread;
            $data_href->{'swrit/s'} = $swrit;
            $data_href->{'fork/s'} = $fork;
            $data_href->{'exec/s'} = $exec;
            $data_href->{'rchar/s'} = $rchar;
            $data_href->{'wchar/s'} = $wchar;
        }
        elsif (my ($procsz, $inodsz, $filesz) = ($line =~ /^\s*(\d+)\/\d+\s+\d+\s+(\d+)\/\d+\s+\d+\s+(\d+)\/\d+\s+\d+\s+\d+\/\d+\s*/))
        {
            $data_href->{'proc-sz'} = $procsz;
            $data_href->{'inod-sz'} = $inodsz;
            $data_href->{'file-sz'} = $filesz;
        }
        elsif(my ($hours, $minutes, $seconds, $msg, $sema) = ($line =~ /^\s*([0-2]*[0-9]):([0-5]*[0-9]):([0-5]*[0-9])\s+(\d+\.\d+)\s+(\d+\.\d+)\s*/))
        {
            $data_href->{'msg/s'} = $msg;
            $data_href->{'sema/s'} = $sema;
            if ($prevhours == 23 && $hours == 0)
            {
                my ($Tsec, $Tmin, $Thour, $Tday, $Tmonth, $Tyear, $Twday, $Tyday, $Tisdst) = localtime(time());
                ($day_href->{'month'}, $day_href->{'day'}, $day_href->{'year'}) = ($Tmonth, $Tday, $Tyear);
            }
            $prevhours=$hours;
            $timestamp = timelocal($seconds, $minutes, $hours, $day_href->{'day'}, $day_href->{'month'}, $day_href->{'year'});
        }
        elsif ($line =~ /^$/)
        {
            if (%{$data_href})
            {
                #print(Dumper($data_href));
                $channel->send([[$CONF->{MEASUREMENT_NAME}, $data_href, {}, $timestamp]]);
                $data_href = {};
            }
        }
        elsif (my ($month, $day, $year) = ($line =~ /([0-1]*[0-9])\/([0-3]*[0-9])\/(\d+)/))
        {
            ($day_href->{'month'}, $day_href->{'day'}, $day_href->{'year'}) = ($month-1, $day, $year);
        }
    }
    close $CMDOUT;
}

exit(0);
