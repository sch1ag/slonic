#!/usr/bin/perl -w
# SimpLe ONline Information Collector: slonic chief

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use POSIX;
use Time::HiRes qw(time);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use POSIX;
use Slonic::Config;
use Slonic::CondChecker qw(check_condition);
use Slonic::OsRecognizer qw(get_os_type);
use Slonic::ChiefOrder;
use Data::Dumper;
use Carp qw(croak);

use Log::Any qw($log);
use Log::Any::Adapter ('Syslog', options  => "pid,ndelay", facility => "daemon");

POSIX::setsid();

my $CFGNAME = "slonic.chief";
$log->notice("Starting normally with config $CFGNAME");

my $CFGOBJ = Slonic::Config->new($CFGNAME);
my $CONF = $CFGOBJ->{CONF};

my $osdata = get_os_type();

my $def_abs_orders_dir = join('/', $CONF->{SLONIC_HOME}, "etc", $CONF->{REL_ORDERS_DIRNAME});
$log->debug("Default order dir is $def_abs_orders_dir"); 

my $cust_abs_orders_dir = join('/', $CONF->{SLONIC_ETC}, $CONF->{REL_ORDERS_DIRNAME});
$log->debug("Custom order dir is $cust_abs_orders_dir"); 

my @orders_files = get_order_files_list($def_abs_orders_dir, $cust_abs_orders_dir);

$log->debugf("Order list is %s", \@orders_files); 

my @orders;
for my $order_file (@orders_files)
{
    my $obj = Slonic::ChiefOrder->new($CONF, $order_file, $osdata);
    $obj->start();
    push(@orders, $obj);
}

my $run=1;
while ($run==1)
{
    for (my $orderi = 0; $orderi < scalar @orders ; $orderi++)
    {
        if (defined $orders[$orderi])
        {
            my $order = $orders[$orderi];
            if ($order->check() != 1)
            {
                $log->warn($order->{NAME}." pid ".$order->{PROC}->pid()." died.");
                $orders[$orderi] = undef;
            }
        }
    }
    sleep $CONF->{CHECK_INTERVAL};
}

sub get_order_files_list {
    my @dirs = @_;
    my %elements;

    for my $curdir (@dirs) 
    {
        if (-d $curdir)
        {
            opendir(my $dh, $curdir) || croak $log->fatal("Can't opendir $curdir: $!");
            my @dirents = readdir($dh);
            closedir $dh;
            my @start_files = grep { /\.json$/ && -f "$curdir/$_" && -s "$curdir/$_"} @dirents;
            for my $start_file (@start_files)
            {
                $elements{$start_file} = 1;
            }
        }
    }
    return keys %elements;
}

