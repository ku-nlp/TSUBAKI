#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use QueryParser;
use TsubakiEngine;

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dfdbdir=s', 'dlengthdbdir=s', 'query=s', 'skippos', 'verbose', 'debug');

if (!$opt{idxdir} || !$opt{dfdbdir} || !$opt{query} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dfdbdir dfdbdir_path -dlengthdbdir doc_lengthdb_dir_path -query QUERY\n";
    exit;
}

my @DF_WORD_DBs = ();
my @DF_DPND_DBs = ();

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
	KNP_OPTIONS => ['-dpnd','-postprocess','-tab']});
    
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}));
    
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
	verbose => $opt{verbose}});
    
    $tsubaki->search($query, \%qid2df);
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
