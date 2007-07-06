#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use QueryParser;
use TsubakiEngine;

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dfdbdir=s', 'dlengthdbdir=s', 'query=s', 'syngraph', 'skippos', 'verbose', 'debug');

if (!$opt{idxdir} || !$opt{dfdbdir} || !$opt{query} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

my @DF_WORD_DBs = ();
my @DF_DPND_DBs = ();

######################################################################
my $N = 51000000;
my $AVE_DOC_LENGTH = 871.925373263118;
# my $AVE_DOC_LENGTH = 483.852649424932;
######################################################################

sub init {
    opendir(DIR, $opt{dfdbdir}) or die;
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	
	my $fp = "$opt{dfdbdir}/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	if (index($cdbf, 'dpnd') > 0) {
	    push(@DF_DPND_DBs, \%dfdb);
	} elsif (index($cdbf, 'word') > 0) {
	    push(@DF_WORD_DBs, \%dfdb);
	}
    }
    closedir(DIR);
}

&main();

sub main {
    &init();

    my $q_parser = new QueryParser({
	KNP_PATH => "$ENV{HOME}/local/bin",
	JUMAN_PATH => "$ENV{HOME}/local/bin",
	SYNDB_PATH => "$ENV{HOME}/SynGraph/syndb/i686",
	KNP_OPTIONS => ['-dpnd','-postprocess','-tab'] });
    
    # logical_cond_qk  クエリ間の論理演算
    # logical_cond_qkw クエリ中の単語間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'AND', logical_cond_qkw => 'AND', syngraph => $opt{syngraph}});
    
    print "*** QUERY ***\n";
    foreach my $qk (@{$query->{keywords}}) {
	print $qk->to_string() . "\n";
	print "*************\n";
    }
    
    my %qid2df = ();
    foreach my $qid (keys %{$query->{qid2rep}}) {
	my $df = &get_DF($query->{qid2rep}{$qid});
	$qid2df{$qid} = $df;
	print "qid=$qid $query->{qid2rep}{$qid} $df\n" if ($opt{debug});
    }

    my $tsubaki = new TsubakiEngine({
	idxdir => $opt{idxdir},
	dlengthdbdir => $opt{dlengthdbdir},
	skip_pos => $opt{skippos},
	verbose => $opt{verbose},
	average_doc_length => $AVE_DOC_LENGTH,
	total_number_of_docs => $N });
    
    my $docs = $tsubaki->search($query, \%qid2df);
    my $hitcount = scalar(@{$docs});

    for (my $rank = 0; $rank < scalar(@{$docs}); $rank++) {
	printf("rank=%d did=%08d score=%f\n", $rank + 1, $docs->[$rank]{did}, $docs->[$rank]{score});
    }
    print "hitcount=$hitcount\n";
}

sub get_DF {
    my ($k) = @_;
    my $k_utf8 = encode('utf8', $k);
    my $gdf = -1;
    my $DFDBs = (index($k, '->') > 0) ? \@DF_DPND_DBs : \@DF_WORD_DBs;
    foreach my $dfdb (@{$DFDBs}) {
 	if (exists($dfdb->{$k_utf8})) {
 	    $gdf = $dfdb->{$k_utf8};
 	    last;
 	}
    }
    return $gdf;
}
