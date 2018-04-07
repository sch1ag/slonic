package Slonic::CondChecker;

use vars;
use strict;
use warnings;

our $VERSION = '1.0.0';

use Math::BooleanEval;
use Carp qw(croak);
use Log::Any qw($log);
use Data::Dumper;
use Exporter qw(import);
our @EXPORT_OK=qw(check_condition);

sub check_condition {
    my $osdata = shift;
    my $condition = shift;

    if (not defined $condition or $condition =~ /^\s*$/)
    {
        $log->warn("The condition is empty or not defined. Returning 0 as whole condition result.");
        return 0;
    }

    my $bool = Math::BooleanEval->new($condition);
 
    # evaluate each defined item in the expression to 1 or 0
    foreach my $item (@{$bool->{'arr'}}){
        next unless defined $item;
        if ($item =~ m/ *([\w_-]+) *(>=|<=|=|<|>|eq) *([\w_-]+) */){
            my $keyparam = $1;
            my $comparator = $2; 
            my $rulevalue = $3; 
            
            if (! exists $osdata->{$keyparam})
            {
                $log->warn("There is no key $keyparam in the data for comparison. Returning 0 as whole condition result.");
                return 0;
            }
         
            if ($comparator ne "eq" && !($osdata->{$keyparam} =~ /^\d+?$/ && $rulevalue =~ /^\d+?$/))
            {
                $log->warn("Parameter: $keyparam Current value: $osdata->{$keyparam} Comparator: $comparator Value in rule: $rulevalue");
                $log->warn("Both args for >= <= = < > operators must be numeric. Returning 0 as whole condition result.");
                return 0;
            }

            $item=0;
            if($comparator eq "eq"){
                if($osdata->{$keyparam} eq $rulevalue){$item=1}
            }
            elsif($comparator eq "="){
                if($osdata->{$keyparam} == $rulevalue){$item=1}
            }
            elsif($comparator eq "<="){
                if($osdata->{$keyparam} <= $rulevalue){$item=1}
            }
            elsif($comparator eq ">="){
                if($osdata->{$keyparam} >= $rulevalue){$item=1}
            }
            elsif($comparator eq ">"){
                if($osdata->{$keyparam} > $rulevalue){$item=1}
            }
            elsif($comparator eq "<"){
                if($osdata->{$keyparam} < $rulevalue){$item=1}
            }

        }
        else
        {
            $log->warn("There is error in expressin $item . Returning 0 as whole condition result.");
            return 0;
        }
    }
        return $bool->eval();
}

1;

