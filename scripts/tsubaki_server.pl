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
use TsubakiEngineFactory;
use CDB_File;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
binmode(STDOUT, ':encoding(euc-jp)');



my $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE = 1;
my $HOSTNAME = `hostname` ; chop($HOSTNAME);

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dlengthdbdir=s', 'port=s', 'skippos', 'verbose', 'debug', 'syngraph', 'anchor', 'idxdir4anchor=s');

if (!$opt{idxdir} || !$opt{port} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dlengthdbdir doc_lengthdb_dir_path -port PORT_NUMBER\n";
    exit;
}

my @DOC_LENGTH_DBs;
opendir(DIR, $opt{dlengthdbdir});
foreach my $dbf (readdir(DIR)) {
    next unless ($dbf =~ /doc_length\.bin/);
    
    my $fp = "$opt{dlengthdbdir}/$dbf";
    
    my $dlength_db;
    # 小規模なテスト用にdlengthのDBをハッシュでもつオプション
    if ($opt{dlengthdb_hash}) {
	require CDB_File;
	tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
    }
    else {
	$dlength_db = retrieve($fp) or die;
    }

    print $fp . "\n";
    push(@DOC_LENGTH_DBs, $dlength_db);
}
closedir(DIR);


my %TITLE_DBs = ();
my %URL_DBs = ();
opendir(DIR, $opt{idxdir});
foreach my $file (readdir(DIR)) {
    my $fp = "$opt{idxdir}/$file";
    if ($file =~ /title.cdb/) {
	tie %TITLE_DBs, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
    }
    elsif ($file =~ /url.cdb/) {
	tie %URL_DBs, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
    }
}
closedir(DIR);

my $hostname = `hostname` ; chop($hostname);
&main();

untie %TITLE_DBs;
untie %URL_DBs;

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
		if ($_ eq "IS_ALIVE\n") {
		    print $new_socket "$HOSTNAME:$opt{port} returns ACK.\n";
		    $new_socket->close();
		    exit;
		}

		if ($_ eq "GET_UPTIME\n") {
		    my $uptime = `uptime` ; chop $uptime;
		    print $new_socket "$HOSTNAME:$opt{port} $uptime\n";
		    $new_socket->close();
		    exit;
		}

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

	    my $factory = new TsubakiEngineFactory(\%opt);
	    my $tsubaki = $factory->get_instance();

	    my $docs = $tsubaki->search($query, $qid2df, {
		flag_of_dpnd_use => $query->{flag_of_dpnd_use},
		flag_of_dist_use => $query->{flag_of_dist_use},
		DIST => $query->{DISTANCE},
		MIN_DLENGTH => $query->{MIN_DLENGTH}});

	    my $hitcount = scalar(@{$docs});
	    # 検索結果の送信
	    if ($query->{only_hitcount}) {
		print $new_socket encode_base64($hitcount, "") , "\n";
		print $new_socket "END_OF_HITCOUNT\n";
	    } else {
		my $ret = [];
		my $docs_size = $hitcount;
		my $results = $query->{results};
		# my $results = ($query->{accuracy}) ? $query->{results} * $query->{accuracy} : $query->{results};
		$results += $query->{start};
		$results = $docs_size if ($docs_size < $results);
		my $max_rank_of_getting_title_and_url = $results * $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE;
		print $query->{results} . "=ret " . $query->{accuracy} . "=acc " . $results . " * " . $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE . " = " . $max_rank_of_getting_title_and_url . "*\n" if ($opt{verbose});

		for (my $rank = 0; $rank < $results; $rank++) {
		    if ($rank < $max_rank_of_getting_title_and_url) {
			my $did = sprintf("%09d", $docs->[$rank]{did});
			$docs->[$rank]{url} = $URL_DBs{$did};
			$docs->[$rank]{title} = $TITLE_DBs{$did};
			$docs->[$rank]{title} = 'no title.' unless ($docs->[$rank]{title});

			print decode('utf8', $docs->[$rank]{title} . "=title, " . $docs->[$rank]{url} . "=url\n") if ($opt{verbose});
		    }
		    $docs->[$rank]{host} = $hostname;
		    push(@{$ret}, $docs->[$rank]);
		}

		print $new_socket encode_base64($hitcount, "") , "\n";
		print $new_socket "END_OF_HITCOUNT\n";

		if ($opt{verbose}) {
		    print Dumper($ret) . "\n";
		    print "-----\n";
		}

		print $new_socket encode_base64(Storable::freeze($ret), "") , "\n";
		print $new_socket "END\n";
	    }
	    $new_socket->close();
	    exit;
	}
    }
}
