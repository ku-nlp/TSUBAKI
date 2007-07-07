#!/usr/bin/env perl

# $Id$

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

my (%opt);
GetOptions(\%opt, 'help', 'dfdbdir=s', 'query=s', 'syngraph', 'host=s', 'port=s');

if (!$opt{port} || !$opt{host} || !$opt{query} || !$opt{dfdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -dfdbdir dfdbdir_path -query string -host hostname -port port_number\n";
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

    my @hosts = ($opt{host});
    my $q_parser = new QueryParser({
	KNP_PATH => "$ENV{HOME}/local/bin",
	JUMAN_PATH => "$ENV{HOME}/local/bin",
	SYNDB_PATH => "$ENV{HOME}/SynGraph/syndb/i686",
	KNP_OPTIONS => ['-dpnd','-postprocess','-tab'] });
    
    # logical_cond_qk  クエリ間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'OR', syngraph => $opt{syngraph}});
    
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

    # 検索クエリの送信
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@hosts); $i++) {
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $hosts[$i],
	    PeerPort => $opt{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die "Cannot connect to the server $hosts[$i]. $!\n";

 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";

	# qid2dfの送信
 	print $socket encode_base64(Storable::freeze(\%qid2df), "") . "\n";
	print $socket "END\n";

	$socket->flush();
    }

    # 検索結果の受信
    my $num_of_sockets = scalar(@hosts);
    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}) {
	    my $buff;
	    my $buff;
	    while (<$socket>) {
		last if ($_ eq "END\n");
		$buff .= $_;
	    }
	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	    
	    my $docs = Storable::thaw(decode_base64($buff));
	    my $hitcount = scalar(@{$docs});

	    for (my $rank = 0; $rank < scalar(@{$docs}); $rank++) {
		printf("rank=%d did=%08d score=%f\n", $rank + 1, $docs->[$rank]{did}, $docs->[$rank]{score});
	    }
	    print "hitcount=$hitcount\n";
	}
    }
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
