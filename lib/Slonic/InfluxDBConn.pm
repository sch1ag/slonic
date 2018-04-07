package Slonic::InfluxDBConn;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use HTTP::Tiny;
use Carp qw(croak);
use Log::Any '$log';
use Time::HiRes qw( time );

sub new {
    my ($class, $params_ref) = @_;
    my $self = {};

    #Expected: idb_host, idb_dbname, idb_consistency, idb_precision, idb_port, idb_user, idb_password, http_keep_alive, http_timeout

    croak $log->fatal("InfluxDB server must be defined") if not defined $params_ref->{idb_host};
    $self->{IDB_HOST} = $params_ref->{idb_host};

    $self->{IDB_PORT} = (defined $params_ref->{idb_port}) ? $params_ref->{idb_port} : 8086;

    $self->{IDB_PROTO} = "http";
    $self->{IDB_RETENTIONPOLICY} = '';

    croak $log->fatal("InfluxDB db name must be defined") if not defined $params_ref->{idb_dbname};
    $self->{IDB_DBNAME} = $params_ref->{idb_dbname};

    $self->{IDB_USER} = (defined $params_ref->{idb_user}) ? $params_ref->{idb_user} : '';
    $self->{IDB_PASSWORD} = (defined $params_ref->{idb_password}) ? $params_ref->{idb_password} : '';
    $self->{IDB_CONSISTENCY} = (defined $params_ref->{idb_consistency}) ? $params_ref->{idb_consistency} : 'all';
    $self->{IDB_PRECISION} = (defined $params_ref->{idb_precision}) ? $params_ref->{idb_precision} : '';
    $self->{IDB_MAX_ROWS_PER_REQ} = (defined $params_ref->{idb_max_rows_per_req}) ? $params_ref->{idb_max_rows_per_req} : 500;

    $self->{HTTP_KEEP_ALIVE} = (defined $params_ref->{http_keep_alive}) ? $params_ref->{http_keep_alive} : 1;
    $self->{HTTP_TIMEOUT} = (defined $params_ref->{http_timeout}) ? $params_ref->{http_timeout} : 10;

    #HTTP::Tiny object
    $self->{HTTP_CONN} = HTTP::Tiny->new((keep_alive => $self->{HTTP_KEEP_ALIVE}, timeout=>$self->{HTTP_TIMEOUT}));

    #Write url
    $self->{WRITE_URL} = undef;

    bless($self, $class);
    
    $self->{WRITE_URL} = $self->_mk_idb_conn_string("write");

    $log->debug("Connection string is $self->{WRITE_URL}");
    return $self;
}


sub write_data {
    my ($self, $dataref)=@_;

    my $elemcount = scalar @{$dataref};
    $log->debug("Going to write $elemcount lines to db by groups of $self->{IDB_MAX_ROWS_PER_REQ} max.");

    my @strings_array;

    for (my $curelem=0; $curelem<$elemcount; $curelem++)
    {
        push(@strings_array, $dataref->[$curelem]);
        if (scalar @strings_array >= $self->{IDB_MAX_ROWS_PER_REQ})
        {
            $self->_write_data_to_db(\@strings_array);
            @strings_array=();
        }
    }
    if (scalar @strings_array > 0)
    {
        $self->_write_data_to_db(\@strings_array);
    } 
}

sub _write_data_to_db {
    my ($self, $strings_array_ref) = @_;
    my $attempt=1;
    my $post_string=join("\n", @{$strings_array_ref});

    #while ($status<200 || $status>299)
    while (1)
    {
        my $req_duration=time();
        my $response = $self->{HTTP_CONN}->request('POST', $self->{WRITE_URL}, {content => $post_string});
        $req_duration=time()-$req_duration;
        $log->debug("Request with " . scalar @{$strings_array_ref} . " lines completed in $req_duration seconds with status $response->{status}.");

        if($response->{status}>=200 && $response->{status}<=299) #Success
        {
            if ($attempt!=1)
            {
                $log->notice("Data was written to DB from the $attempt attempt."); 
            }
            last;
        }
        elsif($response->{status}>=400 && $response->{status}<=499) #InfluxDB could not understand the request
        {
            $log->warning("InfluxDB could not understand the request. Droping bad data. Status is: $response->{status} . Reason is: $response->{reason} .  Content is: $response->{content} ."); 
            last;
        }
        else #Any other status code - wait for some time and retry
        {
            $log->warning("Attempt $attempt to write data to DB was unsuccessful. Status is: $response->{status} . Reason is: $response->{reason} .  Content is: $response->{content} . Still trying."); 
            sleep $self->{HTTP_TIMEOUT};
        }

        $attempt++;
    }
}

sub _mk_idb_conn_string {
    my ($self, $endpoint) = @_;

    my %idbparams = (db => $self->{'IDB_DBNAME'}, consistency => 'all', rp => $self->{'IDB_RETENTIONPOLICY'}, u => $self->{'IDB_USER'}, p => $self->{'IDB_PASSWORD'}, precision => $self->{'IDB_PRECISION'});

    my $server=$self->{IDB_HOST};
    my $port = $self->{IDB_PORT};
    my $proto = $self->{IDB_PROTO};
    $endpoint = "write" if not defined $endpoint;
    my @endpoints = ("write", "query", "ping");
    grep($endpoint eq $_, @endpoints) or croak $log->fatal("Invalid endpoin $endpoint found.");

    my %idb_params_def = (
        db          => {req => 1, def => '', vals => []},
        rp          => {req => 0, def => '', vals => []},
        u           => {req => 0, def => '', vals => []}, #username
        p           => {req => 0, def => '', vals => []}, #password
        precision   => {req => 0, def => '', vals => ["n", "u", "ms", "s", "m", "h"]},
        consistency => {req => 0, def => '', vals => ["one", "quorum", "all", "any"]}
    );

    my %params_hash;
    for my $param (keys %idb_params_def){
        if (defined $idbparams{$param} and $idbparams{$param} ne ""){
            if(scalar @{$idb_params_def{$param}->{vals}} == 0 || grep($idbparams{$param} eq $_, @{$idb_params_def{$param}->{vals}})){
                $params_hash{$param} = $idbparams{$param};
            } else {
                croak $log->fatal("Value $idbparams{$param} is not valid for $param");
            }
        } else {
            if ($idb_params_def{$param}->{def} ne ""){
                $params_hash{$param} = $idb_params_def{$param}->{def};
            } else {
                croak $log->fatal("Requered parameter $param is not defined and didn't have default value") if $idb_params_def{$param}->{req};
            }
        }
    }

    my $params_str = HTTP::Tiny->www_form_urlencode(\%params_hash);
    return "$proto://$server:$port/$endpoint?$params_str";
}

1;
