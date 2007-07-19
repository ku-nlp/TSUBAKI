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
GetOptions(\%opt, 'help', 'dfdbdir=s', 'query=s', 'syngraph', 'host=s', 'port=s', 'hostfile=s', 'debug');

if (((!$opt{port} && !$opt{host})) || !$opt{query} || !$opt{dfdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -dfdbdir dfdbdir_path -query string -host hostname -port port_number\n";
#    exit;
}

my @DF_WORD_DBs = ();
my @DF_DPND_DBs = ();

sub init {
    opendir(DIR, $opt{dfdbdir}) or die;
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	
	my $fp = "$opt{dfdbdir}/$cdbf";
	print $fp . "\n";
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

    my $q_parser = new QueryParser({
	KNP_PATH => "$ENV{HOME}/local/bin",
	JUMAN_PATH => "$ENV{HOME}/local/bin",
	SYNDB_PATH => "$ENV{HOME}/SynGraph/syndb/i686",
#	SYNDB_PATH => "$ENV{HOME}/work/mk_idx_syn2/SynGraph/syndb/i686",
	KNP_OPTIONS => ['-dpnd','-postprocess','-tab'] });
    
    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;

    # logical_cond_qk  クエリ間の論理演算
    my $query = $q_parser->parse(decode('euc-jp', $opt{query}), {logical_cond_qk => 'AND', syngraph => $opt{syngraph}});
    $query->{results} = 50;

    print "*** QUERY ***\n";
    foreach my $qk (@{$query->{keywords}}) {
	print encode('euc-jp', $qk->to_string()) . "\n";
	print "*************\n";
    }

    my %qid2df = ();
    foreach my $qid (keys %{$query->{qid2rep}}) {
	my $df = &get_DF($query->{qid2rep}{$qid});
	$qid2df{$qid} = $df;
	print "qid=$qid ", encode('euc-jp', $query->{qid2rep}{$qid}), " $df\n" if ($opt{debug});
    }

    # 検索クエリの送信
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@hosts); $i++) {
	print $hosts[$i]->{hostname} . "\n";
	print $hosts[$i]->{port} . "\n";
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $hosts[$i]->{hostname},
	    PeerPort => $hosts[$i]->{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die "Cannot connect to the server $hosts[$i]->{host}:$hosts[$i]->{port}. $!\n";

 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";

	# qid2dfの送信
 	print $socket encode_base64(Storable::freeze(\%qid2df), "") . "\n";
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

	    if (defined($buff)) {
		my $hitcount = decode_base64($buff);
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
		# ※受信順をそろえる必要あり
		push(@results, $docs);
	    }

	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }

    my $max = 0;
    my @merged_results;
    my $until = $query->{results};
    while ($until > scalar(@merged_results)) {
	for(my $k = 0; $k < scalar(@results); $k++){
	    next unless (defined($results[$k]->[0]));
	
	    if ($results[$max]->[0]{score} <= $results[$k]->[0]{score}) {
		$max = $k;
	    }
	}
	push(@merged_results, shift(@{$results[$max]}));
    }

    for (my $rank = 0; $rank < scalar(@merged_results); $rank++) {
	printf("rank=%d did=%08d score=%f\n", $rank + 1, $merged_results[$rank]->{did}, $merged_results[$rank]->{score});
    }
    print "hitcount=$total_hitcount\n";
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
