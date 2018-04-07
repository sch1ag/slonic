package Slonic::LocalStorageMgr;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Carp qw(croak);
use POSIX qw(strftime);
use FindBin qw($Script);
use IO::Handle;
use File::Basename;
use Slonic::Utils qw(select_abs_path);

sub new {
    my ($class, $CONF) = @_;
    my $self = {};

    $self->{FILEFH} = undef;
    $self->{DO_STORAGE} = $CONF->{LOCAL_STORAGE};
    $self->{MOD_CURPID}=$$;
    $self->{FILESUFFIX} = defined $CONF->{LOCAL_STORAGE_FILENAME} ? $CONF->{LOCAL_STORAGE_FILENAME} : basename($Script) ;

    if ($self->{DO_STORAGE}){
        $self->{STOREDIR} = select_abs_path($CONF, 'SLONIC_VAR', 'LOCAL_STORAGE_DIR');
        if (not ($self->{STOREDIR} and -d $self->{STOREDIR} and -W $self->{STOREDIR})){
            croak "DIR $self->{STOREDIR} is not defined or not exists or not writable by current user!\n";
        }
    }
    
    bless($self, $class);
    return $self;
}

sub newfile {
    my $self = shift;
    my $filesuffix = shift;

    if ($self->{DO_STORAGE}){

        $self->_closefile();
    
        if (defined $filesuffix){
            $self->{FILESUFFIX} = $filesuffix;
        } 

        $self->_openfile();
    }
}

sub wtiteline {
    my $self = shift;
    my $lineref = shift;

    if ($self->{DO_STORAGE}){
        if (not defined $self->{FILEFH}){
            $self->newfile();
        }
        print { $self->{FILEFH} } $$lineref ;
    }
}

sub _closefile {
    my $self = shift;
    if (defined $self->{FILEFH}){
        close $self->{FILEFH};
        $self->{FILEFH} = undef;
        #TODO: compress closed file in background
    }
}

sub _openfile {
    my $self = shift;
    my $datetime = strftime("%Y.%m.%d-%H.%M.%S", localtime);
    my $filepath = join('/', $self->{STOREDIR}, $datetime.'.'.$self->{FILESUFFIX}.'.pid_'.$self->{MOD_CURPID}.'.out');
    open ($self->{FILEFH}, '+>>', $filepath) or croak "Couldn't open $self->{FILEPATH} : $!\n";
#    $self->{FILEFH}->autoflush(1);
}

1;
