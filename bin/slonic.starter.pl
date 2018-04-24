#!/usr/bin/perl -w
# SimpLe ONline Information Collector: slonic starter

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use POSIX;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Proc::Daemon;
use Data::Dumper;
use Carp qw(croak);

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

if (defined $ENV{'SLONIC_HOME'} && defined $ENV{'SLONIC_VAR'} && -d $ENV{'SLONIC_VAR'} && -d $ENV{'SLONIC_VAR'}.'/log' && defined $ENV{'SLONIC_CHIEF_PIDFILE'})
{
    if(defined $ENV{'SLONIC_USER'} && defined $ENV{'SLONIC_GROUP'})
    {
        my $uid=getpwnam($ENV{'SLONIC_USER'}) || croak $log->fatal("Could not find uid for user $ENV{'SLONIC_USER'}: $!");
        my $gid=getgrnam($ENV{'SLONIC_GROUP'}) || croak $log->fatal("Could not find gid for group $ENV{'SLONIC_GROUP'}: $!");

        #dirty hack to reset supplementary groups 
        $)="$gid $gid";
        ($!==0) || croak $log->fatal("Could not change effecive gid to $ENV{'SLONIC_GROUP'}: $!");

        POSIX::setgid($gid) || croak $log->fatal("Could not change gid to $ENV{'SLONIC_GROUP'}: $!");
        POSIX::setuid($uid) || croak $log->fatal("Could not change uid to $ENV{'SLONIC_USER'}: $!");
    }

    my $chiefcmd = join('/', "/usr/bin/perl " . $ENV{'SLONIC_HOME'}, 'bin', 'slonic.chief.pl');
    my $stdoutfile = join('/', '+>>'.$ENV{'SLONIC_VAR'}, 'log', 'daemon.out');
    my $stderrfile = join('/', '+>>'.$ENV{'SLONIC_VAR'}, 'log', 'daemon.err');

    my $probj = Proc::Daemon->new(
           child_STDOUT => $stdoutfile,
           child_STDERR => $stderrfile,
           file_umask => "026",
           pid_file => $ENV{'SLONIC_CHIEF_PIDFILE'},
           exec_command => $chiefcmd
       );

    my $choldpid = $probj->Init;
    if ($choldpid)
    {
        $log->notice("Slonic Shief Daemon started whith pid $choldpid.");
        exit(0);
    }
}
else
{
    croak $log->fatal("SLONIC_HOME or SLONIC_VAR env is not defined or SLONIC_VAR/log can't be used as log directory or SLONIC_CHIEF_PIDFILE as pidfile.");
}
