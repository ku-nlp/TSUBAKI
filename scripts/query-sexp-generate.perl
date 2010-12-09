#!/usr/bin/env perl

# A generator of query s-expression

# $Id$

use strict;
use warnings;
use QueryParser;
use Tsubaki::TermGroupCreater;
use Configure;
use Getopt::Long;
use Encode;

our $ENCODING = 'utf8'; # euc-jp
binmode(STDOUT, ":encoding($ENCODING)");

my (%opt);
GetOptions(\%opt, 'query=s', 'logical=s', 'syngraph', 'blocktype');

unless ($opt{query}) {
    print STDERR "-query STRING option required.\n";
    exit;
}

$opt{logical} = 'AND' unless ($opt{logical});

my $CONFIG = Configure::get_instance();
my $q_parser = new QueryParser({
    KNP_COMMAND => $CONFIG->{KNP_COMMAND},
    JUMAN_COMMAND => $CONFIG->{JUMAN_COMMAND},
    SYNDB_PATH => $CONFIG->{SYNDB_PATH},
    KNP_OPTIONS => $CONFIG->{KNP_OPTIONS} });
$q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;
my $conditions = {force_dpnd => $opt{force_dpnd}, 
		  is_phrasal_search => -1, # $opt{is_phrasal_search}, 
		  approximate_order => 0, # $opt{approximate_order}, 
		  approximate_dist => 100, # $opt{approximate_dist}, 
		  logical_cond_qkw => 'AND', # $opt{logical_cond_qkw}, 
		 };
my $options = {logical_cond_qk => $opt{logical}, 
	       syngraph => $opt{syngraph}, 
	       blockTypes => $opt{blocktype} ? {':TT' => 1, ':MT' => 1, ':UB' => 1} : {'' => 1}
	      };

my $synresult = $q_parser->_linguisticAnalysis(decode($ENCODING, $opt{query}), $options);
my $root = &Tsubaki::TermGroupCreater::create($synresult, $conditions, $options);
my $sexp = $root->to_S_exp();
$sexp =~ s/\n/ /g;
$sexp =~ s/\s+/ /g;
print '( ', $sexp, " )\n";
