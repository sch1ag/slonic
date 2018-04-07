package Slonic::Utils;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use IO::Handle;
use HTTP::Tiny;
use Time::Local;
use Carp qw(croak);
use FindBin qw($Script);
use File::Basename;
use JSON::PP qw(decode_json);
use Log::Any qw($log);

use Exporter qw(import);
our @EXPORT_OK=qw(strdt2unix trim select_abs_path getruncount slurp read_json_from_file check_bins_fatal check_false check_true check_remote_send);

sub  trim{ my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub select_abs_path {
    my ($cfg, $basepath, $confpath) = @_;

    if (defined $cfg->{$confpath}){
        if($cfg->{$confpath} =~ /^\//){
            return $cfg->{$confpath};
        } else {
            return join('/', $cfg->{$basepath}, $cfg->{$confpath});
        }
    } else {
        croak "$confpath is not defined!\n";
    }
}

sub getruncount {
    my ($PERIOD, $INTERVAL, $OFFSET, $TOLERANCEINTERVAL) = @_;
    my $normoffset=$OFFSET % $PERIOD;

    $TOLERANCEINTERVAL ||= 0;
    #TODO Think about TOLERANCEINTERVAL
    #my $TOLERANCEINTERVAL=($PERIOD<60)?$PERIOD/2:60;

    my $currtime=time();
    my $rest=$currtime % $PERIOD;

    my $nextstart=$currtime-$rest+$normoffset;
    #print "----1->".$nextstart." ".$currtime."\n";
    $nextstart+=$PERIOD if ($nextstart<=$currtime);
    $nextstart+=$PERIOD if ($nextstart-$currtime<=$TOLERANCEINTERVAL);

    my $timetorun = $nextstart - $currtime;
    #print "----2->".$nextstart." ".$currtime."\n";
    #print "----3->".sprintf("%d", $timetorun/$INTERVAL)."\n";
    return sprintf("%d", $timetorun/$INTERVAL);
}

sub strdt2unix {
#  Thu Feb 15 15:00:01 2018
#  Tue Jul 26 20:54:13 MSK 2016
    my %name2indx = (Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5, Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);
    my $strtime = shift;
    chomp $strtime;
 
    my ($mname, $mday, $hour, $min, $sec, $year) = ($strtime=~/\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+([0-3]*[0-9])\s+(\d\d):(\d\d):(\d\d)\s+\w*\s*(2\d\d\d)/);
 
    return timelocal($sec,$min,$hour,$mday,$name2indx{$mname},$year);
}

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or croak ("Could not open file $file");
    local $/ = undef;
    my $cont = <$fh>;
    close $fh;
    return $cont;
}

sub read_json_from_file {
    my $filepathname = shift;
    my $json_text = slurp($filepathname);
    my $json_struct = decode_json $json_text;
    return $json_struct;
}

sub check_bins_fatal
{
    my @cmds=@_;
    for my $cmd (@cmds)
    {
        if (-e $cmd)
        {
            unless (-x $cmd)
            {
                croak($log->fatal("$cmd is not executable by current userid. Exiting."));
            }
        }
        else
        {
            croak($log->fatal("Could not find binary $cmd. Exiting."));
        }
    }
}

sub check_true
{
    my $var=shift;
    if ($var=~/^(on|true|yes|enable|enabled|1)$/i)
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
    if ($var=~/^(off|false|no|disable|disabled|0)$/i)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub check_remote_send
{
    my $CONF=shift;

    if (defined $CONF->{'REMOTE_SEND'} and check_true($CONF->{'REMOTE_SEND'}))
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

1;
