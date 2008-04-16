#!/usr/bin/env perl

# $id:$

use utf8;
use Encode;
use QueryParser;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
use Getopt::Long;
use Configure;

binmode(STDOUT, ':encoding(euc-jp)');

my (%opt);
GetOptions(\%opt, 'query=s', 'logical=s', 'syngraph');

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
my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => $opt{logical}, syngraph => $opt{syngraph}});

print Dumper($query) . "\n";
