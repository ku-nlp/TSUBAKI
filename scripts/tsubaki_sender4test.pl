#!/usr/bin/env perl

# $Id$

use lib '/home/skeiji/work/mg_idx_ntcir3/SearchEngine/scripts';
use strict;
use utf8;
use Encode;
use Getopt::Long;
use QueryParser;
use TsubakiEngine;
use Storable;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use SnippetMaker;
use  TsubakiEngineFactory;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}

binmode(STDOUT, ':encoding(euc-jp)');

my (%opt);
GetOptions(\%opt,
	   'help',
	   'dfdbdir=s',
	   'query=s',
	   'syngraph',
	   'host=s',
	   'port=s',
	   'hostfile=s',
	   'gold_data=s',
	   'qid=s',
	   'results=s',
	   'dist_on',
	   'dpnd_on',
	   'without_reps',
	   'snippet',
	   'debug',
	   'distance=s',
	   'trim',
	   'min_dlength=s',
	   'weight_NE=s',
	   'weight_head=s',
	   'weight_CN=s',
	   'weight_NE_MOD=s',
	   'local',
	   'const=s'
    );


my $BORNUS = 1;
my $MAX_NUM_OF_WORDS_IN_SNIPPET = 300;

tie my %did2dir, 'CDB_File', "/home/skeiji/work/mg_idx_ntcir3/SearchEngine/scripts/did2dir.cdb" or die;
tie my %synonyms, 'CDB_File', "/home/skeiji/work/mg_idx_ntcir3/SearchEngine/scripts/syndb.mod.cdb" or die;
my $SF_DIR_PREFIX = '/net2/nlpcf34/disk03/skeiji/ntcir3/xmls';
$SF_DIR_PREFIX = '/net2/nlpcf34/disk03/skeiji/ntcir3/xmls_w_syngraph' if ($opt{syngraph});
my $HTML_DIR_PREFIX = '/net2/nlpcf34/disk03/skeiji/ntcir3/htmls';


sub load_golddata {
    my ($fp) = @_;
    open(READER, $fp) or die;
    my %golddata = ();
    while (<READER>) {
	my ($qid, $judge, $did, $dumy) = split(/\t/, $_);
	my $key = "$qid:$did";

	if ($judge eq 'H' || $judge eq 'S') {
	    $golddata{$key} = "★★★";
	}
	elsif ($judge eq 'A') {
	    $golddata{$key} = "★★";
	}
	elsif ($judge eq 'B') {
	    $golddata{$key} = "★";
	}
	elsif ($judge eq 'C') {
	    $golddata{$key} = "×";
	}
    }
    close(READER);

    return \%golddata;
}

my $golddata = {};
$golddata = &load_golddata($opt{gold_data}) if ($opt{gold_data});

&main();

sub main {
    $opt{dfdbdir} = "/home/skeiji/data/dfdbs_ntcir3_syngraph" if ($opt{syngraph});
    my $q_parser = new QueryParser({
	KNP_PATH => ($opt{syngraph}) ? "$ENV{HOME}/novel/tools/080215/bin" : "$ENV{HOME}/novel/tools/bin",
	JUMAN_PATH => ($opt{syngraph}) ? "$ENV{HOME}/novel/tools/080215/bin" : "$ENV{HOME}/novel/tools/bin",
	SYNDB_PATH => "$ENV{HOME}/work/mg_idx_ntcir3/SearchEngine/scripts/SynGraph/syndb/i686",
	INDEXER_OPTIONS => {without_using_repname => $opt{without_reps}, ignore_yomi => 1},
	KNP_OPTIONS => ($opt{syngraph}) ? ['-dpnd','-postprocess','-tab','-ne-crf'] :  ['-dpnd','-postprocess','-tab','-ne-crf'],
	QUERY_TRIMMING => $opt{trim},
	JYUSHI => {NE => $opt{weight_NE}, HEAD => $opt{weight_head}, CN => $opt{weight_CN}},
	KEISHI => {NE_MOD => $opt{weight_NE_MOD}},
	DFDB_DIR => $opt{dfdbdir} });

    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;

    # logical_cond_qk  クエリ間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => $opt{const}, syngraph => $opt{syngraph}});
    $query->{results} = $opt{results};
    $query->{flag_of_dpnd_use} = $opt{dpnd_on};
    $query->{flag_of_dist_use} = $opt{dist_on};
    $query->{DISTANCE} = $opt{distance};
    $query->{DISTANCE} = 30 unless ($opt{distance});
    $query->{MIN_DLENGTH} = $opt{min_dlength};
    $query->{MIN_DLENGTH} = 0 unless ($opt{min_dlength});

    print "\n********** QUERY *********\n";
    foreach my $qk (@{$query->{keywords}}) {
	print $qk->to_string_verbose() . "\n";
    }

    $q_parser->query_trim($query);

    foreach my $qk (@{$query->{keywords}}) {
	unless ($query->{flag_of_dpnd_use}) {
	    $qk->{dpnds} = [];
	}
    }


    print "********* REQUEST *********\n";
    foreach my $qk (@{$query->{keywords}}) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		my $qid = $rep->{qid};
		my $df = $query->{qid2df}{$qid};
		my $qtf = $query->{qid2qtf}{$qid};
		my $weight = $query->{gid2weight}{$rep->{gid}};
		if ($opt{syngraph}) {
		    printf("gid=$query->{qid2gid}{$qid} qid=$qid $query->{qid2rep}{$qid} df=$df qtf=%.3f weight=%.3f (%s)\n", $qtf, $weight, decode('utf8', $synonyms{$query->{qid2rep}{$qid}})); # if ($opt{debug});
		} else {
		    printf("gid=$query->{qid2gid}{$qid} qid=$qid $query->{qid2rep}{$qid} df=$df qtf=%.3f weight=%.3f\n", $qtf, $weight); # if ($opt{debug});
		}

	    }
	    print "-----\n";
	}

	print "--------------------------\n";
	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		my $qid = $rep->{qid};
		my $df = $query->{qid2df}{$qid};
		my $qtf = $query->{qid2qtf}{$qid};

		printf("qid=$qid $query->{qid2rep}{$qid} df=$df weight=%.3f\n", $qtf); # if ($opt{debug});
	    }
	    print "-----\n";
	}
	print "**************************\n\n";
    }
    my $results = &search($query);

    my $rank = -1;
    for (my $k = 0; $k < scalar(@$results); $k++) {
	my $did = sprintf("%09d", $results->[$k]{did});
	my $score = $results->[$k]{score_total};
	my $score_w = $results->[$k]{score_word};
	my $score_d = $results->[$k]{score_dpnd};
	my $score_n = $results->[$k]{score_dist};
	my $q2score = $results->[$k]{q2score};

	my $dlength = undef;
	foreach my $qid (keys %{$q2score->{word}}) {
	    $dlength = $q2score->{word}{$qid}{dlength};
	    last if (defined $dlength);
	}

	my $key = "$opt{qid}:NW$did";
	my $judge = (exists $golddata->{$key}) ? $golddata->{$key} : '？';

#	next if ($judge eq '？');
	$rank++;
#	last if ($rank > 1000);

	my $xdir = $did2dir{$did};
	my ($hdir) = ($xdir =~ /x(\d+)/);
	my $xmlfile = "$SF_DIR_PREFIX/$xdir/NW$did.data.xml";
	my $htmlfile = "$HTML_DIR_PREFIX/$hdir/NW$did.data.gz";

	print "\n----------\n";
	printf("rank=%d did=%s score=%.3f %s (w=%.3f d=%.3f n=%.3f) dlength=%.2f\n", $rank + 1, $did, $score, $judge, $score_w, $score_d, $score_n, $dlength);
	print "----------\n";

	foreach my $type ('word', 'dpnd', 'near') {
	    if ($type eq 'near') {
		foreach my $qid (sort {$a <=> $b} keys %{$q2score->{$type}}) {
		    my $rep = $query->{qid2rep}{$qid};
		    my $kakarisaki_qid = $query->{qid2rep}{$q2score->{$type}{$qid}{kakarisaki_qid}};
		    my $kakarisaki_rep = $kakarisaki_qid;

		    printf("%s::%s dist=%d (%d) df=%.2f qtf=%.2f dlength=%.2f score=%.3f\n",
			   $rep,
			   $kakarisaki_rep,
			   $q2score->{$type}{$qid}{dist},
			   $q2score->{$type}{$qid}{DIST},
			   $q2score->{$type}{$qid}{df},
			   $q2score->{$type}{$qid}{qtf},
			   $q2score->{$type}{$qid}{dlength},
			   $q2score->{$type}{$qid}{score});
		}
	    } else {
		foreach my $qid (sort {$a <=> $b} keys %{$q2score->{$type}}) {
		    my $rep;
		    if ($opt{syngraph}) {
			my $gid = $qid;
			foreach my $q_id (@{$query->{gid2qids}{$gid}}) {
			    $rep .= ($query->{qid2rep}{$q_id} . " (gid=$gid)\n");
			}
		    } else {
			$rep = $query->{qid2rep}{$qid};
		    }

		    printf("%s tf=%.2f df=%.2f qtf=%.2f dlength=%.2f score=%.3f\n",
			   $rep,
			   $q2score->{$type}{$qid}{tf},
			   $q2score->{$type}{$qid}{df},
			   $q2score->{$type}{$qid}{qtf},
			   $q2score->{$type}{$qid}{dlength},
			   $q2score->{$type}{$qid}{score});
		}
	    }
	    print "----------\n";
	}

#	printf("%s\t0\tNW%s\t%d\t%.3f\tNTCIR_FORMAT_TSUBAKI\n", $opt{qid}, $did, $rank + 1, $score);
	printf("%s\t0\tNW%s\t%d\t%.8f\tNTCIR_FORMAT_TSUBAKI %s\n", $opt{qid}, $did, $rank + 1, (1 - ($rank / 1000)), $judge);
	print "----------\n";
	printf("rank=%d %s\n", $rank + 1, $xmlfile);
	printf("rank=%d %s\n", $rank + 1, $htmlfile);
	print "----------\n";
	
	my $wordcnt = 0;
	my %snippets = ();
	my %sbuf = ();
	if ($opt{snippet}) {
	    my $sentences;
	    if ($opt{syngraph}) {
		$sentences = &SnippetMaker::extract_sentences_from_standard_format($query->{keywords}, $xmlfile . ".gz", {window_size => 10, unzipped => 0});
	    } else {
		$sentences = &SnippetMaker::extract_sentences_from_standard_format($query->{keywords}, $xmlfile, {window_size => 10, unzipped => 1});
	    }

	    foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score}} @{$sentences}) {
		next if (exists($sbuf{$sentence->{rawstring}}));
		$sbuf{$sentence->{rawstring}} = 1;

		my $sid = $sentence->{sid};
		my $length = $sentence->{length};
		my $num_of_whitespaces = $sentence->{num_of_whitespaces};

		next if ($num_of_whitespaces / $length > 0.2);

		for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		    $snippets{$sid} .= $sentence->{surfs}[$i];
		    $wordcnt++;
		
		    # スニペットが N 単語を超えた終了
		    if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET) {
			$snippets{$sid} .= " ...";
			last;
		    }
		}
		# ★ 多重 foreach の脱出に label をつかう
		last if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET);
	    }

	    my $snippet;
	    my $prev_sid = -1;
	    foreach my $sid (sort {$a <=> $b} keys %snippets) {
		if ($sid - $prev_sid > 1 && $prev_sid > -1) {
		    $snippet .= " ... " unless ($snippet =~ /\.\.\.$/);
		}
		$snippet .= $snippets{$sid};
		$prev_sid = $sid;
	    }

	    $snippet =~ s/S\-ID:\d+//g;
	    $snippet = decode('utf8', $snippet) unless (utf8::is_utf8($snippet));
	    print $snippet . "\n";
	}
    }

#   print "hitcount=$total_hitcount\n";
}

sub access_to_localdisk {
    my ($query, $qid2df) = @_;

    my $qid2df = $query->{qid2df};
    my %opt = ();
    $opt{idxdir} = "/work/skeiji/mg_idx_ntcir3_syngraph/1";
    $opt{dlengthdbdir} = "/work/skeiji/mg_idx_ntcir3_syngraph/1";
    $opt{syngraph} = 1;

    my $factory = new TsubakiEngineFactory(\%opt);
    my $tsubaki = $factory->get_instance();

    my $docs = $tsubaki->search($query, $qid2df, {
	flag_of_dpnd_use => $query->{flag_of_dpnd_use},
	flag_of_dist_use => $query->{flag_of_dist_use},
	DIST => $query->{DISTANCE},
	MIN_DLENGTH => $query->{MIN_DLENGTH}});

    my $hitcount = scalar(@{$docs});
    my $ret = [];
    $query->{results} = $hitcount if ($query->{results} < 0);
    if ($hitcount < $query->{results}) {
	$ret = $docs;
    } else {
	my $docs_size = $hitcount;
	my $results = ($query->{accuracy}) ? $query->{results} * $query->{accuracy} : $query->{results};
	$results += $query->{start};
	$results = $docs_size if ($docs_size < $results);
	for (my $rank = 0; $rank < $results; $rank++) {
# 	    if ($rank < $MAX_RANK_FOR_SETTING_URL_AND_TITLE) {
# 		my $did = sprintf("%09d", $docs->[$rank]{did});
#		$docs->[$rank]{url} = $URL_DBs{$did};
#		$docs->[$rank]{title} = $TITLE_DBs{$did};
# 		$docs->[$rank]{title} = 'no title.' unless ($docs->[$rank]{title});
# 	    }
#	    print "rank=$rank did=$docs->[$rank]{did}\n";
	    push(@{$ret}, $docs->[$rank]);
	}
    }

    return ($hitcount, [$ret]);
}

sub search {
    my ($query) = @_;

    my $qid2df = $query->{qid2df};
    my ($hitcount, $results) = ($opt{local}) ? &access_to_localdisk($query, $qid2df) : &access_to_server($query, $qid2df);

    my %did_buf;
    my $max = 0;
    my @merged_results;
    my $until = ($hitcount > $query->{results}) ? $query->{results} : $hitcount;
    my $nokori = $query->{results} - $until;
    print "hit=$hitcount nokori=$nokori\n";
#   print STDERR "hit=$hitcount nokori=$nokori\n";
    while ($until > scalar(@merged_results)) {
	for(my $k = 0; $k < scalar(@$results); $k++){
	    next unless (defined($results->[$k][0]));
	
	    if ($results->[$max][0]{score_total} <= $results->[$k][0]{score_total}) {
		$max = $k;
	    }
	}
	last unless (defined $results->[$max]);

	push(@merged_results, shift(@{$results->[$max]}));
	$did_buf{$merged_results[-1]->{did}} = 1;
    }

#    return \@merged_results;

    my @ret = sort {$b->{score_total} <=> $a->{score_total} ||
			$a->{did} <=> $b->{did}} @merged_results;
    @merged_results = @ret;

    if ($hitcount >= $query->{results} && $hitcount > 0) {
	return \@merged_results;
    } else {
	# 必須を消して再検索
	foreach my $qk (@{$query->{keywords}}) {
	    foreach my $reps (@{$qk->{dpnds}}) {
		foreach my $rep (@$reps) {
		    $rep->{requisite} = undef;
		}
	    }
	}

	foreach my $q (@{$query->{keywords}}) {
	    $q->{logical_cond_qkw} = 'OR';
	    $q->{near} = -1;
	}
	$query->{logical_cond_qk} = 'OR';
	$query->{near} = -1;

	my ($hitcount, $results) = ($opt{local}) ? &access_to_localdisk($query, $qid2df) : &access_to_server($query, $qid2df);
	my @ret = sort {$b->{score_total} <=> $a->{score_total} ||
			    $a->{did} <=> $b->{did}} @$results;
	$results = \@ret;
	my $until = $query->{results};
	$max = 0;
	while ($until > scalar(@merged_results)) {
	    for (my $k = 0; $k < scalar(@$results); $k++){
		next unless (defined($results->[$k][0]));
	
		if ($results->[$max][0]{score_total} <= $results->[$k][0]{score_total}) {
		    $max = $k;
		}
	    }

	    my $d = shift(@{$results->[$max]});
	    unless (exists $did_buf{$d->{did}}) {
		push(@merged_results, $d);
	    }
	}
	return \@merged_results;
    }
}

sub access_to_server {
    my ($query, $qid2df) = @_;

    my @hosts = ();
    unless ($opt{hostfile}) {
	push(@hosts, {hostname => $opt{host}, port => $opt{port}});
    } else {
	open(READER, $opt{hostfile}) or die;
	while (<READER>) {
	    chop($_);
	    my ($hostname, $port) = split(' ', $_);
	    push(@hosts, {hostname => $hostname, port => $port});
	}
	close(READER);
    }

    # 検索クエリの送信
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@hosts); $i++) {
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $hosts[$i]->{hostname},
	    PeerPort => $hosts[$i]->{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die "Cannot connect to the server $hosts[$i]->{hostname} $hosts[$i]->{host}:$hosts[$i]->{port}. $!\n";

 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";

	# qid2dfの送信
 	print $socket encode_base64(Storable::freeze($qid2df), "") . "\n";
	print $socket "END\n";

	$socket->flush();
    }

    # 検索結果の受信
    my @results = ();
    my $total_hitcount = 0;
    my $num_of_sockets = scalar(@hosts);
    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}) {
	    my $buff = undef;
	    while (<$socket>) {
		last if ($_ eq "END_OF_HITCOUNT\n");
		$buff .= $_;
	    }

	    my $hitcount = 0;
	    if (defined($buff)) {
		$hitcount = decode_base64($buff);
		$total_hitcount += $hitcount;
	    }

	    my $docs;
	    unless ($query->{only_hitcount}) {
		$buff = undef; 
		while (<$socket>) {
		    last if ($_ eq "END\n");
		    $buff .= $_;
		}
		$docs = Storable::thaw(decode_base64($buff)) if (defined($buff));
		if ($hitcount > 0) {
		    push(@results, $docs);
		}
	    }

	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }
    @results = sort {$a->[0]{did} <=> $b->[0]{did}} @results;
    return ($total_hitcount, \@results);
}
