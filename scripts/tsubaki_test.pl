#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use QueryParser;
use TsubakiEngineFactory;
use Time::HiRes;

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dfdbdir=s', 'dlengthdbdir=s', 'query=s', 'syngraph', 'skippos', 'dlengthdb_hash', 'hypocut=i', 'weight_dpnd_score=f', 'verbose', 'debug', 'show_speed');

if (!$opt{idxdir} || !$opt{dfdbdir} || !$opt{query} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

my @DF_WORD_DBs = ();
my @DF_DPND_DBs = ();

sub init {
    my $start_time = Time::HiRes::time;
    opendir(DIR, $opt{dfdbdir}) or die;
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	
	my $fp = "$opt{dfdbdir}/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
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
}

&main();

sub main {
    &init();

    my $syngraph_option = { relation => 1, antonym => 1};
    $syngraph_option->{hypocut_attachnode} = $opt{hypocut} ? $opt{hypocut} : 9;

    my $q_parser = new QueryParser({
	KNP_PATH => "$ENV{HOME}/local/bin",
	JUMAN_PATH => "$ENV{HOME}/local/bin",
	SYNDB_PATH => "$ENV{HOME}/tmp/SynGraph/syndb/i686",
#	SYNDB_PATH => "$ENV{HOME}/cvs/SearchEngine/scripts/tmp/SearchEngine/scripts/tmp/SynGraph/syndb/i686",
	KNP_OPTIONS => ['-dpnd','-postprocess','-tab'],
	SYNGRAPH_OPTION => $syngraph_option,
	SHOW_SPEED => $opt{show_speed}
    });
    
    # logical_cond_qk : クエリ間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'OR', syngraph => $opt{syngraph}});
    
    print "*** QUERY ***\n";
    foreach my $qk (@{$query->{keywords}}) {
	print encode('euc-jp', $qk->to_string()) . "\n";
	print "*************\n";
    }

    my %qid2df = ();
    foreach my $qid (keys %{$query->{qid2rep}}) {
	my $df = &get_DF($query->{qid2rep}{$qid});
	$qid2df{$qid} = $df;
	print "qid=$qid ", encode('euc-jp', $query->{qid2rep}{$qid}), " $df\n" if ($opt{verbose});
    }

    my $factory = new TsubakiEngineFactory(\%opt);
    my $tsubaki = $factory->get_instance();

    my $docs = $tsubaki->search($query, \%qid2df);
    my $hitcount = scalar(@{$docs});

    for (my $rank = 0; $rank < scalar(@{$docs}); $rank++) {
	printf("rank=%d did=%09d score=%f\n", $rank + 1, $docs->[$rank]{did}, $docs->[$rank]{score_total});
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
