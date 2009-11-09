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
# use Configure;
use RequestParser;
use Storable;


binmode(STDIN,  ':utf8');
binmode(STDOUT, ':encoding(euc-jp)');
binmode(STDERR, ':encoding(euc-jp)');

my (%opt);
GetOptions(\%opt,
	   'help',
	   'idxdir=s',
	   'dfdbdir=s',
	   'dlengthdbdir=s',
	   'query=s',
	   'syngraph',
	   'english',
	   'lemma',
	   'disable_query_processing',
	   'disable_syngraph',
	   'skippos',
	   'dlengthdb_hash',
	   'hypocut=i',
	   'weight_dpnd_score=f',
	   'verbose',
	   'debug',
	   'show_speed',
	   'anchor',
	   'idxdir4anchor=s',
	   'logging_query_score',
	   'results=s',
	   'score_verbose',
	   'disable_synnode',
	   'stdin',
	   'show_time');

if (!$opt{idxdir} || (!$opt{query} && !$opt{stdin}) || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

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


my @DOC_LENGTH_DBs;
opendir(DIR, $opt{dlengthdbdir});
foreach my $dbf (readdir(DIR)) {
    my $dlength_db = undef;
    if ($dbf =~ /(\d+).doc_length\.bin$/) {
	my $fp = "$opt{dlengthdbdir}/$dbf";

	if ($opt{dlengthdb_hash}) {
	    require CDB_File;
	    tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	}
	else {
	    $dlength_db = retrieve($fp) or die;
	}
    }
    elsif ($dbf =~ /(\d+).doc_length\.txt$/) {
	$dlength_db = ();
	open (FILE, "$opt{dlengthdbdir}/$dbf") or die "$!";
	while (<FILE>) {
	    chop;
	    my ($did, $length) = split (/ /, $_);
	    $dlength_db->{$did + 0} = $length;
	}
	close (FILE);
    }

    push(@DOC_LENGTH_DBs, $dlength_db) if (defined $dlength_db);
}
closedir(DIR);


# my $CONFIG = Configure::get_instance();

# $CONFIG->{USE_OF_QUERY_PARSE_SERVER} = 0;

&main();

sub main {
    my $params = RequestParser::getDefaultValues(0);

    $params->{query} = decode('euc-jp', $opt{query});
    $params->{syngraph} = $opt{syngraph};
    $params->{disable_synnode} = $opt{disable_synnode};
    $params->{verbose} = $opt{verbose};
    $params->{antonym_and_negation_expansion} = 0;
    $params->{DFDB_DIR} = $opt{dfdbdir} if ($opt{dfdbdir});

    if ($opt{disable_query_processing}) {
	$params->{telic_process} = 0;
	$params->{CN_process} = 0;
	$params->{NE_process} = 0;
	$params->{modifier_of_NE_process} = 0;
	$params->{use_of_NE_tagger} = 0;
    }

    if ($opt{stdin}) {
	while (<STDIN>) {
	    chop;
	    $params->{query} = $_;
	    &search($params);
	}
    } else {
	&search($params);
    }
}

sub search {
    my ($params) = @_;

    my $logger = new Logger();
    my $loggerAll = new Logger();

    my $query = &createQueryObject($params, $logger, $loggerAll);

    $opt{doc_length_dbs} = \@DOC_LENGTH_DBs;
    my $factory = new TsubakiEngineFactory(\%opt);
    my $tsubaki = $factory->get_instance();
    $loggerAll->setTimeAs('create_TSUBAKI_instance_time', '%.3f');

    my $docs = $tsubaki->search($query, $query->{qid2df}, {flag_of_dpnd_use => 1, flag_of_dist_use => 1, flag_of_anchor_use => ($opt{idxdir4anchor}) ? 1 : 0, DIST => 30, weight_of_tsubaki_score => 1, verbose => $opt{verbose}, results => $opt{results}, LOGGER => $logger});
#    $loggerAll->setTimeAs('search_time', '%.3f');


#     my $merge = 0;
#     foreach my $k ($logger->keys()) {
# 	next unless ($k =~ /merge_synonyms_and_repnames_of_/);
# 	$merge += $logger->getParameter($k);
#     }

    my $hitcount = scalar(@{$docs});

#   &printLog($hitcount, $merge, $logger, $loggerAll, $LOGGER) if ($opt{show_time});
    &output($docs, $params, $hitcount);
}

sub printLog {
    my ($hitcount, $merge, $logger, $loggerAll, $LOGGER) = @_;

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

sub createQueryObject {
    my ($params, $logger, $loggerAll) = @_;

    my $query;
    if ($opt{english}) {
	my $isPhrasalSearch = 0;
	# フレーズ検索かどうかのチェック
	if ($opt{query} =~ /^'.+'$/) {
	    $isPhrasalSearch = 1;
	    $opt{query} =~ s/^\'//;
	    $opt{query} =~ s/\'$//;
	}

	my %param = ();
	my @words = ();
	my $qid = 0;
	my $gid = 0;
	my $num_of_words = 0;
	my %qid2gid = ();
	my %qid2qtf = ();

	my $lemmatizer;
	if ($opt{lemma}) {
	    require Lemmatize;
	    $lemmatizer = new Lemmatize();
	}

	foreach my $word (split (" ", $opt{query})) {
	    my @terms;

	    print $word . " -> " if ($opt{debug});
	    if ($opt{lemma}) {
		my $lemmatized_word = $lemmatizer->lemmatize($word, '');
		$word = (defined $lemmatized_word) ? $lemmatized_word : $word;
		$word .= "*";
		$word = lc($word);
	    }

	    print $word . "\n" if ($opt{debug});

	    my $term = {
		requisite => 1,
		string => $word,
		qid => $qid,
		qid => $gid,
		syngraph => 1
		};
	    $qid2gid{$qid} = $gid;
	    $qid2qtf{$qid} = 1;

	    $param{qid2df}->{$qid++} = 1;
	    push (@terms, $term);

	    # 同義語を考慮したい場合は@termに追加する

	    push (@words, \@terms);
	    $gid++;
	    $num_of_words++;
	}

	push (@{$param{keywords}},
	      {
		  near => $num_of_words,
		  logical_cond_qkw => 'AND',
		  syngraph => 1,
		  words => \@words,
		  keep_order => 1
		});
	$param{qid2gid} = \%qid2gid;
	$param{qid2qtf} = \%qid2qtf;
	$query = new Query(\%param);
    } else {
	$query = RequestParser::parseQuery($params, $logger);
    }
    $loggerAll->setTimeAs('query_parse_time', '%.3f');

    if ($opt{debug} && !$opt{english}) {
	print "*** QUERY ***\n";
	foreach my $qk (@{$query->{keywords}}) {
	    # print Dumper($qk) . "\n";
	    print $qk->to_string_verbose() . "\n";
	    print "*************\n";
	}
    }
    return $query;
}

sub output {
    my ($docs, $params, $hitcount) = @_;

    my $results = ($hitcount < $opt{results} || $opt{results} < 0) ? $hitcount :$opt{results};
    for (my $rank = 0; $rank < $results; $rank++) {
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
	    if ($opt{stdin}) {
		printf("query=%s rank=%d did=%s score=%.3f\n", $params->{query}, $rank + 1, $did, $score);
	    } else {
		printf("rank=%d did=%s score=%.3f\n", $rank + 1, $did, $score);
	    }
	}
    }
    print "hitcount=$hitcount\n";
}
