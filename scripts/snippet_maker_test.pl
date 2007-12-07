#!/usr/bin/env perl

use SnippetMaker;
use utf8;
use strict;
use QueryParser;
use Getopt::Long;
use Encode;

my $TOOL_HOME = "$ENV{HOME}/local/bin";
my $KNP_PATH = $TOOL_HOME;
my $JUMAN_PATH = $TOOL_HOME;
my $SYNDB_PATH = "$ENV{HOME}/tmp/SynGraph/syndb/i686";

my (%opt);
GetOptions(\%opt, 'query=s', 'z', 'syngraph', 'debug', 'encoding=s', 'discard_title');

require SynGraph if ($opt{syngraph});
$opt{encoding} = 'euc-jp' unless ($opt{encoding});

binmode(STDOUT, ':encoding(euc-jp)');

&main();

sub init_query_parser {
    my $q_parser = new QueryParser({
	KNP_PATH => $KNP_PATH,
	JUMAN_PATH => $JUMAN_PATH,
	SYNDB_PATH => $SYNDB_PATH,
	KNP_OPTIONS => ['-postprocess','-tab'] });
    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;

    return $q_parser;
}

sub main {
    # クエリの解析
    my $q_parser = &init_query_parser();
    my $query = $q_parser->parse(decode($opt{encoding}, $opt{query}), {logical_cond_qk => 'AND', syngraph => $opt{syngraph}});

    if ($opt{debug}) {
	print "*** QUERY ***\n";
	foreach my $qk (@{$query->{keywords}}) {
	    print $qk->to_string() . "\n";
	    print "*************\n";
	}
    }

    foreach my $id (@ARGV) {
#	my $sentences = &SnippetMaker::extract_sentences_from_standard_format($query->{keywords}, $file, \%opt);
	my $sentences = &SnippetMaker::extract_sentences_from_ID($query->{keywords}, $id, \%opt);
	foreach my $s (@$sentences) {
	    print $id . " ";
	    print "sid " . $s->{sid} . " ";
	    print "score " . $s->{score} . " ";
	    print "smoothed " . $s->{smoothed_score} . " ";
	    printf("whitespace %.2f ", $s->{num_of_whitespaces} / $s->{length});

	    print $s->{rawstring} . "\n";
	}
    }
}