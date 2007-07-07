#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Storable;
use MIME::Base64;
use IO::Socket;
use Storable;
use QueryParser;
use TsubakiEngine;

my $N = 51000000;
my $AVE_DOC_LENGTH = 871.925373263118;

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dlengthdbdir=s', 'port=s', 'skippos', 'verbose', 'debug');

if (!$opt{idxdir} || !$opt{port} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dlengthdbdir doc_lengthdb_dir_path -port PORT_NUMBER\n";
    exit;
}

&main();

sub main {

    my $listening_socket = IO::Socket::INET->new(
	LocalPort => $opt{port},
	Listen    => SOMAXCONN,
	Proto     => 'tcp',
	Reuse     => 1);

    unless ($listening_socket) {
	my $host = `hostname`; chop($host);
	die "Cannot listen port No. $opt{port} on $host. $!\n";
	exit;
    }

    # 検索クエリを待つ
    while (1) {
	my $new_socket = $listening_socket->accept();
	my $client_sockaddr = $new_socket->peername();
	my($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
	my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
	my $client_ip = inet_ntoa($client_iaddr);
	
	select($new_socket); $|=1; select(STDOUT);
	
	my $pid;
	if ($pid = fork()) {
	    $new_socket->close();
	    wait;
	} else {
	    select($new_socket); $|=1; select(STDOUT);

	    # 検索クエリの受信
	    my $buff;
	    while (<$new_socket>) {
		last if ($_ eq "EOQ\n");
		$buff .= $_;
	    }
	    my $query = Storable::thaw(decode_base64($buff));

	    # qid2dfの受信
	    $buff = undef;
	    while (<$new_socket>) {
		last if ($_ eq "END\n");
		$buff .= $_;
	    }
	    my $qid2df = Storable::thaw(decode_base64($buff));

	    print "*** QUERY ***\n";
	    foreach my $qk (@{$query->{keywords}}) {
		print $qk->to_string() . "\n";
		print "*************\n";
	    }

	    my $tsubaki = new TsubakiEngine({
		idxdir => $opt{idxdir},
		dlengthdbdir => $opt{dlengthdbdir},
		skip_pos => $opt{skippos},
		verbose => $opt{verbose},
		average_doc_length => $AVE_DOC_LENGTH,
		total_number_of_docs => $N });
	    
	    my $docs = $tsubaki->search($query, $qid2df);

	    # 検索結果の送信
	    if ($query->{only_hitcount}) {
		my $hitcount = scalar(@{$docs});
		print $new_socket encode_base64(Storable::freeze($hitcount)) , "\n";
	    } else {
		print $new_socket encode_base64(Storable::freeze($docs)) , "\n";
		print $new_socket "END\n";
	    }

	    $new_socket->close();
	    exit;
	}
    }
}
