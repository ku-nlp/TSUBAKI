#!/usr/bin/env perl

# $Id$

# クエリ処理用サーバー

use strict;
use utf8;
use Encode;
use MIME::Base64;
use IO::Socket;
use Storable;
use Logger;
use Configure;
use QueryParser;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

binmode(STDOUT, ':encoding(utf8)');
binmode(STDERR, ':encoding(utf8)');



my $HOSTNAME = `hostname | cut -f 1 -d .` ; chop($HOSTNAME);

my $CONFIG = Configure::get_instance();

&main();

sub main {
    my $PORT = shift @ARGV;
    my $listening_socket = IO::Socket::INET->new(
	LocalPort => $PORT,
	Listen    => SOMAXCONN,
	Proto     => 'tcp',
	Reuse     => 1);

    unless ($listening_socket) {
	my $host = `hostname`; chop($host);
	printf STDERR ("[QUERY PARSE SERVER] Can't listen the given port (num=%d,host=%s). Maybe the port is already used.\n", $PORT, $host);
	exit;
    }

    push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});
    require SynGraph;

    my $SYNGRAPH = new SynGraph($CONFIG->{SYNDB_PATH});
    while (1) {
	my $new_socket = $listening_socket->accept();
	my $client_sockaddr = $new_socket->peername();
	my ($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
	my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
	my $client_ip = inet_ntoa($client_iaddr);

	select($new_socket); $|=1; select(STDOUT);

	my $pid;
	if ($pid = fork()) {
	    $new_socket->close();
	    wait;
	} else {
	    select($new_socket); $|=1; select(STDOUT);

	    my $logger = new Logger();
	    my $buff;
	    while (<$new_socket>) {
		last if ($_ eq "EOD\n");
		$buff .= $_;
	    }
	    my $params = Storable::thaw(decode_base64($buff));
	    
	    my $q_parser = new QueryParser({
		DFDB_DIR => $CONFIG->{SYNGRAPH_DFDB_PATH},
		ignore_yomi => $CONFIG->{IGNORE_YOMI},
		use_of_case_analysis => $params->{use_of_case_analysis},
		use_of_NE_tagger => $params->{use_of_NE_tagger},
		debug => $params->{debug},
		option => $params });

	    # set parameters
	    $params->{logger} = $logger;
	    $params->{logical_cond_qk} = $params->{logical_operator};

	    # クエリの解析
	    # logical_cond_qk: クエリ間の論理演算
	    my $query = $q_parser->parse($params->{query}, $params);

	    # sending log data in a search slave server.
	    print $new_socket encode_base64(Storable::nfreeze($logger), "") , "\n";
	    print $new_socket "EOL\n";

	    $query->{option}{SYNGRAPH} = undef;

	    print $new_socket encode_base64(Storable::nfreeze($query), "") , "\n";
	    print $new_socket "EOD\n";

	    $new_socket->close();
	    exit;
	}
    }
}
