#!/usr/bin/env perl

use SnippetMaker;
use utf8;
use strict;
use QueryParser;
use Getopt::Long;
use Encode;
use Data::Dumper;

my $TOOL_HOME = "$ENV{HOME}/local/bin";
my $KNP_PATH = $TOOL_HOME;
my $JUMAN_PATH = $TOOL_HOME;
my $SYNDB_PATH = "$ENV{HOME}/cvs/SynGraph/syndb/i686";

my (%opt);
GetOptions(\%opt,
	   'query=s',
	   'z',
	   'syngraph',
	   'start=s',
	   'end=s',
	   'pos=s',
	   'encoding=s',
	   'discard_title',
	   'window_size=s',
	   'kwic',
	   'kwic_window_size=s',
	   'use_of_repname_for_kwic',
	   'use_of_katuyou_for_kwic',
	   'use_of_dpnd_for_kwic',
	   'use_of_huzokugo_for_kwic',
	   'use_of_negation_for_kwic',
	   'syndb=s',
	   'string_mode',
	   'is_old_version',
	   'uniq',
	   'debug',
	   'english',
	   'new_sf'
    );

$SYNDB_PATH = $opt{syndb} if ($opt{syndb});
$opt{kwic_window_size} = 5 unless ($opt{kwic_window_size});

require SynGraph if ($opt{syngraph});
$opt{encoding} = 'utf8' unless ($opt{encoding});

$opt{IS_ENGLISH_VERSION} = $opt{english};
$opt{USE_NEW_STANDARD_FORMAT} = $opt{IS_ENGLISH_VERSION} ? 1 : $opt{new_sf};

$opt{verbose} = 1 if $opt{debug};

binmode(STDOUT, ":encoding($opt{encoding})");
binmode(STDERR, ":encoding($opt{encoding})");

&main();


sub main {
    # クエリの解析
    my $q_parser = new QueryParser(\%opt);
    my $query = $q_parser->parse(decode($opt{encoding}, $opt{query}), {logical_cond_qk => 'AND', syngraph => $opt{syngraph}});

    if ($opt{debug}) {
	print "*** QUERY ***\n";
	print Dumper($query);
    }

    my %pos2qid = ();
    my $k = 0;
    foreach my $p (split (/,/, $opt{pos})) {
	$pos2qid{$p} = $k++;
    }
    $pos2qid{628}--;
    $opt{pos2qid} = \%pos2qid;

    foreach my $file (@ARGV) {
	my $sentences = &SnippetMaker::extract_sentences_from_standard_format($query->{keywords}, $file, \%opt);
#	my $sentences = &SnippetMaker::extract_sentences_from_ID($query->{keywords}, $id, \%opt);
	foreach my $s (@$sentences) {
	    if ($opt{kwic}) {
		print join("|", @{$s->{contextsL}}) . " ";
		print "[" . $s->{keyword} . "] ";
		print join("|", @{$s->{contextsR}}) . "\n";
	    } else {
		print $s->{including_all_indices} . " ";
		print $file . " ";
		print "para " . $s->{paraid} . " ";
		print "sid " . $s->{sid} . " ";
		print "score " . sprintf ("%.3f", $s->{score}) . " ";
		print "smoothed " . sprintf ("%.3f", $s->{smoothed_score}) . " ";
		printf("whitespace %.2f ", $s->{num_of_whitespaces} / $s->{length});
		print " $s->{rawstring}\n";
	    }
	}
    }
}
