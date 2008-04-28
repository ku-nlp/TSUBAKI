#!/usr/bin/env perl

# $Id$

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

binmode(STDOUT, ':encoding(euc-jp)');
binmode(STDERR, ':encoding(euc-jp)');

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dfdbdir=s', 'dlengthdbdir=s', 'query=s', 'syngraph', 'skippos', 'dlengthdb_hash', 'hypocut=i', 'weight_dpnd_score=f', 'verbose', 'debug', 'show_speed', 'anchor', 'idxdir4anchor=s');

if (!$opt{idxdir} || !$opt{dfdbdir} || !$opt{query} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

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

&main();

sub main {
    # &init();

    my $DFDB_DIR = ($opt{syngraph} > 0) ? $CONFIG->{SYNGRAPH_DFDB_PATH} : $CONFIG->{ORDINARY_DFDB_PATH};
    my $q_parser = new QueryParser({ DFDB_DIR => $DFDB_DIR, verbose => $opt{verbose} });

    # logical_cond_qk : クエリ間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'OR', syngraph => $opt{syngraph}});

    print "*** QUERY ***\n";
    foreach my $qk (@{$query->{keywords}}) {
	print $qk->to_string_verbose() . "\n";
	print "*************\n";
    }

    my $factory = new TsubakiEngineFactory(\%opt);
    my $tsubaki = $factory->get_instance();

    my $docs = $tsubaki->search($query, $query->{qid2df}, {flag_of_dpnd_use => 1, flag_of_dist_use => 1, DIST => 30, verbose => $opt{verbose}});

    my $hitcount = scalar(@{$docs});

    for (my $rank = 0; $rank < scalar(@{$docs}); $rank++) {
	my $did = sprintf("%09d", $docs->[$rank]{did});
	my $score = $docs->[$rank]{score_total};
	my $score_w = $docs->[$rank]{score_word};
	my $score_d = $docs->[$rank]{score_dpnd};
	my $score_n = $docs->[$rank]{score_dist};

	printf("rank=%d did=%s score=%.3f (w=%.3f d=%.3f n=%.3f)\n", $rank + 1, $did, $score, $score_w, $score_d, $score_n);
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
