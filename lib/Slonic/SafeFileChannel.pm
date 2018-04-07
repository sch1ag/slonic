package Slonic::SafeFileChannel;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Fcntl qw(:flock);
use Carp qw(croak);
use Log::Any qw($log);

#use File::stat;

sub new {
    my ($class, $params_ref) = @_;
    my $self = {};

    #Expected: filename, lockretry, lockwaittime, maxfilesize

    croak $log->fatal("File for locking must be defined") if not defined $params_ref->{filename};
    $self->{FILENAME} = $params_ref->{filename};
    $log->debug("Creating SafeFileChannel based on file $self->{FILENAME}.");
    $self->{LOCKNAME} = $params_ref->{filename}.".lock";
    
    $params_ref->{lockretry}=3 if not defined $params_ref->{lockretry};
    $self->{LOCKRETRY} = $params_ref->{lockretry};

    $params_ref->{lockwaittime}=0.3 if not defined $params_ref->{lockwaittime};
    $self->{LOCKWAITTIME} = $params_ref->{lockwaittime};

    $params_ref->{maxfilesize}=0 if not defined $params_ref->{maxfilesize};
    $self->{MAXFILESIZE} = $params_ref->{maxfilesize};

    $self->{LOCKFH} = undef;
    $self->{FILEFH} = undef;
    $self->{LOCKED} = 0;

    bless($self, $class);
    return $self;
}

sub _lock {
    my $self = shift;

    return 1 if ($self->{LOCKED});

    open ($self->{LOCKFH}, '+>>', $self->{LOCKNAME}) or croak $log->fatal("Couldn't open $self->{LOCKNAME} : $!");

    for (my $try=0; $try<$self->{LOCKRETRY}; $try++){
        if (flock($self->{LOCKFH}, LOCK_EX | LOCK_NB)){
            $self->{LOCKED} = 1;
            return 1;
        }
        $log->debug("Locking $self->{LOCKNAME}. Retry $try.");
        select(undef, undef, undef, $self->{LOCKWAITTIME});
    }

    #could not lock file
    #closing file and returning zero
    close $self->{LOCKFH};
    return 0;
}

sub _unlock {
    my $self = shift;
    return 1 if (not $self->{LOCKED});

    if (close($self->{LOCKFH})){
        $self->{LOCKED} = 0;
        return 1;
    } else {
        return 0;
    }
}

sub _append {
    my $self = shift;
    my $dataref = shift;

    my $appendfh;
    open ($appendfh, '>>', $self->{FILENAME}) or croak $log->fatal("Couldn't open $self->{FILENAME} : $!");
    
    my $i=0;
    for my $wline (@{$dataref}){
        print $appendfh $wline."\n" ;
        $i++;
    }
    close($appendfh);
    return $i;
}

sub _read {
    my $self = shift;

    my @data;

    my $fh;
    open ($fh, '<', $self->{FILENAME}) or croak $log->fatal("Couldn't open $self->{FILENAME} : $!");

    while (my $rline = <$fh>){
        chomp $rline;
        push(@data, $rline);
    }
    close($fh);

    return \@data;
}

sub _trunc {
    my $self = shift;

    #truncate file
    open (my $fh, '>', $self->{FILENAME}) or croak $log->fatal("Couldn't open $self->{FILENAME} : $!");
    close($fh);
}


#Try to lock file and append it
#users: modules
sub append {
    my $self = shift;
    my $dataref = shift;
    my $ret = 0;

    if ($self->_lock()){
        my $filesize=(-f $self->{FILENAME}) ? (stat($self->{FILENAME}))[7] : 0;
        if ($self->{MAXFILESIZE}!=0 && $filesize>=$self->{MAXFILESIZE}){
            $log->warn("File $self->{FILENAME} is too big. $filesize more than $self->{MAXFILESIZE}. Truncating.");
            $self->_trunc();
        }
        $ret=$self->_append($dataref);
        $self->_unlock();
    }
    return $ret;
}

#Check size. If non zero: try to lock file (with retry), read all data and truncate file.
#user: daemon
sub read_and_trunc {
    my $self = shift;
    my $dataref;

    if (-e $self->{FILENAME} && -s $self->{FILENAME})
    {
        if ($self->_lock()){
            $dataref=$self->_read();
            $self->_trunc();
            $self->_unlock();
        }
    }
    return $dataref;
}

#Lock file and check it size. If zero - delete file and its lockfile. Unlock file. 
sub delete_if_empty {
    my $self = shift;
    $log->debug("Cheking file $self->{FILENAME} for zero size");
    if ($self->_lock()){
        if (-z $self->{FILENAME}){
            $log->debug("File $self->{FILENAME} is zero size. Deleting it and its lock.");
            unlink $self->{FILENAME};
            unlink $self->{LOCKNAME};
            $self->_unlock();
            return 0;
        } else {
            $self->_unlock();
            return 1;
        }
    } else {
        $log->warn("Could not lock file $self->{FILENAME} to check size. Returning 1 to use this object");
        return 1;
    }
}

1;
