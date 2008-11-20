#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use MIME::Base64;
use IO::Socket;
use Storable;
use SnippetMaker;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

use Configure;

my $CONFIG = Configure::get_instance();

binmode(STDOUT, ":encoding(euc-jp)");

my $MAX_NUM_OF_WORDS_IN_SNIPPET = 100;
my $HOSTNAME = `hostname` ; chop($HOSTNAME);

my (%opt);
GetOptions(\%opt, 'help', 'port=s', 'z', 'string_mode', 'is_old_version', 'ignore_yomi', 'verbose');

if (!$opt{port} || $opt{help}) {
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

    # 問い合わせを待つ
    while (1) {
	my $new_socket;
	my $client_hostname;

	my $new_socket = $listening_socket->accept();
	my $client_sockaddr = $new_socket->peername();
	my($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
	my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
	
	select($new_socket); $|=1; select(STDOUT);
	
	my $pid;
	if ($pid = fork()) {
	    $new_socket->close();
	    wait;
	} else {
	    print "cactch query from $client_hostname.\n" if ($opt{verbose});

	    select($new_socket); $|=1; select(STDOUT);

	    # クエリの受信
	    my $buff;
	    while (<$new_socket>) {
		# サーバーがダウンしていないかどうかのチェックモード
		if ($_ eq "IS_ALIVE\n") {
		    print $new_socket "$HOSTNAME:$opt{port} returns ACK.\n";
		    $new_socket->close();
		    exit;
		}
		elsif ($_ =~ /GET_SFDAT (\d+)$/) {
		    my $did = $1;
		    my $xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $CONFIG->{DIR_PREFIX_FOR_SFS_W_SYNGRAPH}, $did / 1000000, $did / 10000, $did);
		    my $buf;
		    open(READER, "zcat $xmlfile |");
		    while (<READER>) {
			$buf .= $_;
		    }
		    close(READER);
		    print $new_socket $buf;
		    exit;
		}

		# 通常モード
		last if ($_ eq "EOQ\n");
		$buff .= $_;
	    }
	    my $query = Storable::thaw(decode_base64($buff));
	    print "restore query $client_hostname.\n" if ($opt{verbose});

	    # スニペッツを生成する文書IDの取得
	    $buff = undef;
	    while (<$new_socket>) {
		last if ($_ eq "EOD\n");
		$buff .= $_;
	    }
	    my $docs = Storable::thaw(decode_base64($buff));
	    print "restore docs $client_hostname.\n" if ($opt{verbose});

	    # スニペッツ生成のオプションを取得
	    $buff = undef;
	    while (<$new_socket>) {
		last if ($_ eq "EOO\n");
		$buff .= $_;
	    }
	    my $option = Storable::thaw(decode_base64($buff));
	    $option->{string_mode} = $opt{string_mode};
	    $option->{is_old_version} = $opt{is_old_version};
	    $option->{ignore_yomi} = $opt{ignore_yomi};
	    $option->{z} = $opt{z};

	    if ($opt{verbose}) {
		print "begin with snippet creation $client_hostname.\n";
		print "-----\n";
		print Dumper ($option);
		print "-----\n";
		print Dumper ($query);
		print "-----\n";
	    }

	    # スニペッツの生成
	    my %result = ();
	    foreach my $doc (@{$docs}) {
		my $did = $doc->{did};
		print $did . "\n" if ($opt{verbose});
		$option->{start} = $doc->{start};
		$option->{end} = $doc->{end};
		$option->{qid2pos} = $doc->{qid2pos};
		$result{$did} = &SnippetMaker::extract_sentences_from_ID($query->{keywords}, $did, $option);
		# print Dumper($result{$did}) . "\n" if ($HOSTNAME =~ /nlpc33/);
	    }
	    print "finish of snippet creation for $client_hostname @ $HOSTNAME\n" if ($opt{verbose});

	    # スニペッツの送信
	    print $new_socket encode_base64(Storable::freeze(\%result), "") , "\n";
	    print $new_socket "HOSTNAME $HOSTNAME\n";
	    print $new_socket "END\n";
	    
	    $new_socket->close();
	    exit;
	}
    }
}
