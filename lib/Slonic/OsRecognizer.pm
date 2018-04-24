package Slonic::OsRecognizer;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Carp qw(croak);
use POSIX;
use Log::Any qw($log);
use Data::Dumper;
use Exporter qw(import);
our @EXPORT_OK=qw(get_os_type);

sub get_os_type {
    my %osdata = (
        "OSNAME"      => "", # AIX SunOS Linux HP-UX
        "VERSION"     => "",
        "RELEASE"     => "",
        "LINUX_DISTR" => "", # rhel, ubuntu
        "AIX_TL"      => "",
        "AIX_SP"      => "",
        "ARCH"        => ""
    );

    my %DistrID2LinuxDistr = (
        "RedHatEnterpriseServer" => "rhel",
        "Ubuntu" => "ubuntu"
    );

    my ($osname, $nodename, $release, $version, $machine) = POSIX::uname();
    $osdata{'OSNAME'} = $osname;

    if ($osname eq "AIX")
    {
        $osdata{'VERSION'} = $version;
        $osdata{'RELEASE'} = $release;
        my $oslevel = `oslevel -s`;
        if ($oslevel =~ m{^(\d+)-(\d+)-(\d+)-(\d+)$})
        {
            $osdata{'AIX_TL'} = $2;
            $osdata{'AIX_SP'} = $3;
        }
    }
    elsif ($osname eq "SunOS")
    {
        ($osdata{'VERSION'}) = ($release =~ /5\.(\d+)/);
        $osdata{'RELEASE'} = 0;
        if ($osdata{'VERSION'} == 11 && $version =~ /11\.(\d+)/)
        {
            ($osdata{'RELEASE'}) = ($version =~ /11\.(\d+)/);
        }
    }
    elsif ($osname eq "Linux")
    {
        my $release_file = "/etc/os-release";
        if ( -f $release_file )
        {
            open(my $fh, $release_file) or croak $log->fatal("Could not open file $release_file $!");
            while (my $row = <$fh>)
            {
                chomp $row;
                if ($row =~ m{^ID=(.*)$})
                {
                    $osdata{'LINUX_DISTR'} = $1;
                }
                elsif ($row =~ m{^VERSION_ID="(\d+)\.(\d+)"$})
                {
                    $osdata{'VERSION'} = $1;
                    $osdata{'RELEASE'} = $2;
                }
            }
            close $fh;
        }
        else {
            system("type lsb_release");
            if ( $? == 0)
            {
                my @lsb_release = `lsb_release -a`;
                for my $row (@lsb_release)
                {
                    if ($row =~ m{^Distributor ID: (.*)$})
                    {
                        if (exists $DistrID2LinuxDistr{$1})
                        {
                            $osdata{'LINUX_DISTR'} = $DistrID2LinuxDistr{$1};
                        }
                    }
                    elsif ($row =~ m{^Release:\s+(\d+)\.(\d+)$})
                    {
                        $osdata{'VERSION'} = $1;
                        $osdata{'RELEASE'} = $2;
                    }
                }
            }
        }
    }
    elsif ($osname eq "HP-UX")
    {
        (my $trash, $osdata{'VERSION'}, $osdata{'RELEASE'}) = split('\.', $version);
    }

    $log->debug("OS recognized as:", \%osdata);
    return \%osdata;
}

1;
