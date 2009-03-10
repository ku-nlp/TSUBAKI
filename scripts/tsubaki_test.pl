#!/usr/bin/env perl

# $Id$

use Logger;
my $LOGGER = new Logger();

use strict;
use utf8;
use Encode;
use Getopt::Long;
use QueryParser;
use TsubakiEngineFactory;
use Time::HiRes;
use Data::Dumper;
use CDB_File;
use Configure;
use RequestParser;


binmode(STDOUT, ':encoding(euc-jp)');
binmode(STDERR, ':encoding(euc-jp)');

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dfdbdir=s', 'dlengthdbdir=s', 'query=s', 'syngraph', 'skippos', 'dlengthdb_hash', 'hypocut=i', 'weight_dpnd_score=f', 'verbose', 'debug', 'show_speed', 'anchor', 'idxdir4anchor=s', 'logging_query_score', 'results=s', 'score_verbose', 'disable_synnode', 'show_time');

if (!$opt{idxdir} || !$opt{query} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

$opt{syngraph} = 1;
$opt{results} = 1000 unless ($opt{results});
$opt{score_verbose} = 1 if ($opt{debug});

my @DF_WORD_DBs = ();
my @DF_DPND_DBs = ();


sub init {
    print STDERR "loading dfdb files... " if ($opt{verbose});
    my $start_time = Time::HiRes::time;
    opendir(DIR, $opt{dfdbdir}) or die;
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb.\d+/);

	my $fp = "$opt{dfdbdir}/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$!: can't tie to $fp $!\n";
	if (index($cdbf, 'dpnd') > -1) {
	    push(@DF_DPND_DBs, \%dfdb);
	} elsif (index($cdbf, 'word') > -1) {
	    push(@DF_WORD_DBs, \%dfdb);
	}
    }
    closedir(DIR);
    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($opt{show_speed}) {
	printf ("@@@ %.4f sec. dfdb loading.\n", $conduct_time);
    }
    print STDERR "done.\n" if ($opt{verbose});
}

my $CONFIG = Configure::get_instance();

$CONFIG->{USE_OF_QUERY_PARSE_SERVER} = 0;

&main();

sub main {
    # &init();

    my $params = RequestParser::getDefaultValues(0);

    $params->{query} = decode('euc-jp', $opt{query});
    $params->{syngraph} = $opt{syngraph};
    $params->{disable_synnode} = $opt{disable_synnode};
    $params->{verbose} = $opt{verbose};
    $params->{antonym_and_negation_expansion} = 0;
    $params->{DFDB_DIR} = $opt{dfdbdir} if ($opt{dfdbdir});

    # logical_cond_qk : クエリ間の論理演算
    # my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'OR', syngraph => $opt{syngraph}});

    my $logger = new Logger();
    my $loggerAll = new Logger();

    my $query = RequestParser::parseQuery($params, $logger);
    $loggerAll->setTimeAs('query_parse_time', '%.3f');

    if ($opt{debug}) {
	print "*** QUERY ***\n";
	foreach my $qk (@{$query->{keywords}}) {
	    # print Dumper($qk) . "\n";
	    print $qk->to_string_verbose() . "\n";
	    print "*************\n";
	}
    }

    my $factory = new TsubakiEngineFactory(\%opt);
    my $tsubaki = $factory->get_instance();
    $loggerAll->setTimeAs('create_TSUBAKI_instance_time', '%.3f');

    my $docs = $tsubaki->search($query, $query->{qid2df}, {flag_of_dpnd_use => 1, flag_of_dist_use => 1, flag_of_anchor_use => 1, DIST => 30, verbose => $opt{verbose}, results => $opt{results}, LOGGER => $logger});
    $loggerAll->setTimeAs('search_time', '%.3f');

    my $merge = 0;
    foreach my $k ($logger->keys()) {
	next unless ($k =~ /merge_synonyms_and_repnames_of_/);
	$merge += $logger->getParameter($k);
    }

    my $hitcount = scalar(@{$docs});


    if ($opt{show_time}) {
	print "query: " . decode('euc-jp', $opt{query}) . "\n";
	print "hitcount: " . $hitcount . "\n";
	print "query parse time: " . $loggerAll->getParameter('query_parse_time') . "\n";
	print "create TSUBAKI instance time: " . $loggerAll->getParameter('create_TSUBAKI_instance_time') . "\n";
	print "search time: " . $loggerAll->getParameter('search_time') . "\n";
	print "  normal search time: " . $logger->getParameter('normal_search') . "\n";
	print "    index access time: " . $logger->getParameter('index_access') . "\n";
	print "    merge synonyms time: " . $merge . "\n";
	print "  logical condition time: " . $logger->getParameter('logical_condition') . "\n";
	print "  near condition time: " . $logger->getParameter('near_condition') . "\n";
	print "  merge dids time: " . $logger->getParameter('merge_dids') . "\n";
	print "  document scoring time: " . $logger->getParameter('document_scoring') . "\n";
	print "----------------------------------\n";

	$LOGGER->setTimeAs('total', '%.3f');
	print "total time: " . $LOGGER->getParameter('total') . "\n";
	print "----------------------------------\n";
	exit;
    }


    $opt{results} = ($hitcount < $opt{results} || $opt{results} < 0) ? $hitcount :$opt{results};
    for (my $rank = 0; $rank < $opt{results}; $rank++) {
	my $did = sprintf("%09d", $docs->[$rank]{did});
	my $score = $docs->[$rank]{score_total};
	my $start = $docs->[$rank]{start};
	my $end = $docs->[$rank]{end};
	my $pos2qid = join (",", sort keys %{$docs->[$rank]{pos2qid}});
	my $score_w = $docs->[$rank]{score_word};
	my $score_d = $docs->[$rank]{score_dpnd};
	my $score_n = $docs->[$rank]{score_dist};
	my $score_aw = $docs->[$rank]{score_word_anchor};
	my $score_ad = $docs->[$rank]{score_dpnd_anchor};

	if ($opt{debug}) {
	    printf("rank=%d did=%s score=%.3f start=%d end=%d pos=%s (w=%.3f d=%.3f n=%.3f aw=%.3f ad=%.3f)\n", $rank + 1, $did, $score, $start, $end, $pos2qid, $score_w, $score_d, $score_n, $score_aw, $score_ad);
	} else {
	    printf("rank=%d did=%s score=%.3f\n", $rank + 1, $did, $score);
	}
    }
    print "hitcount=$hitcount\n";
}

sub get_DF {
    my ($k) = @_;

    my $start_time = Time::HiRes::time;
    my $k_utf8 = encode('utf8', $k);
    my $gdf = -1;
    my $DFDBs = (index($k, '->') > 0) ? \@DF_DPND_DBs : \@DF_WORD_DBs;
    foreach my $dfdb (@{$DFDBs}) {
	$gdf = $dfdb->{$k_utf8};
	last if (defined $gdf);
    }

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($opt{show_speed}) {
	printf ("@@@ %.4f sec. df value loading (key=%s).\n", $conduct_time, encode('euc-jp', $k));
    }

    return $gdf;
}
