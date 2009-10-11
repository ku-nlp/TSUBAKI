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

binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

use Logger;
use Configure;


my $CONFIG = Configure::get_instance();

my $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE = 1;
my $HOSTNAME = `hostname | cut -f 1 -d .` ; chop($HOSTNAME);

my (%opt);
GetOptions(\%opt, 'help', 'idxdir=s', 'dlengthdbdir=s', 'port=s', 'skippos', 'verbose', 'debug', 'syngraph', 'idxdir4anchor=s');

if (!$opt{idxdir} || !$opt{port} || !$opt{dlengthdbdir} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dlengthdbdir doc_lengthdb_dir_path -port PORT_NUMBER\n";
    exit;
}

my $ID;
my @DOC_LENGTH_DBs;
opendir(DIR, $opt{dlengthdbdir});
foreach my $dbf (readdir(DIR)) {
    if ($CONFIG->{IS_NICT_MODE}) {
	next unless ($dbf =~ /(\d+).doc_length\.txt$/);
    
	$ID = $1;
	my $fp = "$opt{dlengthdbdir}/$dbf";
	my $dlength_db;
	open (READER, $fp) or die "$!";
	while (<READER>) {
	    chop;
	    my ($sid, $length) = split (/ /, $_);
	    $dlength_db->{$sid} = $length;
	}
	close (READER);

	push(@DOC_LENGTH_DBs, $dlength_db);
    } else {
	next unless ($dbf =~ /(\d+).doc_length\.bin$/);
    
	$ID = $1;
	my $fp = "$opt{dlengthdbdir}/$dbf";
    
	my $dlength_db;
	if ($opt{dlengthdb_hash}) {
	    require CDB_File;
	    tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	}
	else {
	    $dlength_db = retrieve($fp) or die;
	}

	push(@DOC_LENGTH_DBs, $dlength_db);
    }
}
closedir(DIR);

my %tid2sid = ();
my $sid2tid_file = "$opt{idxdir}/sid2tid";
if (-e $sid2tid_file) {
    open (READER, $sid2tid_file) or die "$!";
    while (<READER>) {
	chop;
	my ($sid, $tid) = split (/ /, $_);
	$tid2sid{$tid} = $sid;
    }
    close (READER);
}

my %TITLE_DBs = ();
my %URL_DBs = ();
my %PAGERANK_DB = ();
opendir(DIR, $opt{idxdir});
foreach my $file (readdir(DIR)) {
    my $fp = "$opt{idxdir}/$file";
    if ($file =~ /title.cdb/) {
	tie my %tmp, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	while (my ($k, $v) = each %tmp) {
	    $TITLE_DBs{$k} = $v;
	}
	untie %tmp;
    }
    elsif ($file =~ /url.cdb/) {
	tie my %tmp, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	while (my ($k, $v) = each %tmp) {
	    $URL_DBs{$k} = $v;
	}
	untie %tmp;
    }
    elsif ($file =~ /pagerank.txt/) {
	open (FILE, sprintf (qw(%s/%s), $opt{idxdir}, $file)) or die "$!\n";
	while (<FILE>) {
	    chop;
	    my ($did, $score) = split (/ /, $_);
	    $PAGERANK_DB{$did} = $score;
	}
	close (FILE);
    }

}
closedir(DIR);


my %STOP_PAGE_LIST = ();
if ($CONFIG->{IS_NICT_MODE}) {
    my $rmfile = "$opt{idxdir}/rmfiles";
    if (-e $rmfile) {
	open (F, $rmfile) or die "$!";
	while (<F>) {
	    chop;
	    $STOP_PAGE_LIST{$_} = 1;
	}
	close (F);
    }
} else {
    if ($CONFIG->{STOP_PAGE_LIST}) {
	open (FILE, $CONFIG->{STOP_PAGE_LIST}) or die "$!\n";
	while (<FILE>) {
	    next if ($_ =~ /^\#/);

	    chop;
	    $STOP_PAGE_LIST{$_} = 1;
	}
	close (FILE);
    }
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

    syswrite STDERR, "[TSUBAKI SERVER] READY! (host=$HOSTNAME, port=$opt{port}, dir=$opt{idxdir}, id=$ID, rmfiles=" . scalar (keys %STOP_PAGE_LIST) . ")\n";
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

	    $buff = undef;
	    while (<$new_socket>) {
		last if ($_ eq "END\n");
		$buff .= $_;
	    }
	    my $qid2df = Storable::thaw(decode_base64($buff));
	    # スレーブサーバーへの送信にかかった時間をロギング
	    my $logger = $query->{logger};
	    $logger->setTimeAs('transfer_time_to', '%.3f');


	    $opt{score_verbose} = $query->{score_verbose};
	    $opt{logging_query_score} = $query->{logging_query_score};
	    $opt{doc_length_dbs} = \@DOC_LENGTH_DBs;
	    $opt{pagerank_db} = \%PAGERANK_DB;

	    my $factory = new TsubakiEngineFactory(\%opt);
	    my $tsubaki = $factory->get_instance();

	    # 検索している文書セットのIDを保持
	    $logger->setParameterAs('id', $ID);

	    # 検索結果
	    my $docs = [];

	    # サイト検索の場合
	    if ($query->{only_sitesearch}) {
		while (my ($did, $url) = each %URL_DBs) {
		    if (index ($url, $query->{option}{site}) > -1) {
			push (@$docs, {did => $did, url => $url, score_total => 10000000 / ($did + 1)});
		    }
		}
	    }
	    # 通常検索の場合
	    else {
		$docs = $tsubaki->search($query, $qid2df, {
		    flag_of_dpnd_use => $query->{flag_of_dpnd_use},
		    flag_of_dist_use => $query->{flag_of_dist_use},
		    flag_of_anchor_use => $query->{flag_of_anchor_use},
		    flag_of_pagerank_use => $query->{flag_of_pagerank_use},
		    weight_of_tsubaki_score => $query->{WEIGHT_OF_TSUBAKI_SCORE},
		    c_pagerank => $query->{C_PAGERANK},
		    DIST => $query->{DISTANCE},
		    MIN_DLENGTH => $query->{MIN_DLENGTH},
		    LOGGER => $logger });
	    }

	    # 通信に要する時間を測定するためにクリアする
	    $logger->clearTimer();


	    # sending log data in a search slave server.
	    my %hostinfo;
	    $hostinfo{name} = $HOSTNAME;
	    $hostinfo{port} = $opt{port};
	    print $new_socket encode_base64(Storable::nfreeze(\%hostinfo), "") , "\n";
	    print $new_socket "END_OF_HOST\n";

	    print $new_socket encode_base64(Storable::nfreeze($logger), "") , "\n";
	    print $new_socket "END_OF_LOGGER\n";

	    my $hitcount = scalar(@{$docs});
	    if ($query->{only_hitcount}) {
		print $new_socket encode_base64($hitcount, "") , "\n";
		print $new_socket "END_OF_HITCOUNT\n";
	    } else {

		# サイト指定検索の場合
		if (defined $query->{option}{site} && !$query->{only_sitesearch}) {
		    my $filteredDocs = [];
		    for (my $i = 0; $i < scalar(@$docs); $i++) {
			my $did = sprintf("%09d", $docs->[$i]{did});
			$docs->[$i]{url} = $URL_DBs{$did};
			next unless ($docs->[$i]{url} =~ m!\Q$query->{option}{site}\E!);

			push (@$filteredDocs, $docs->[$i]);
		    }
		    $docs = $filteredDocs;
		    $hitcount = scalar(@$filteredDocs);
		}


		my $ret = [];
		my $docs_size = $hitcount;


		# 特定の文書IDを持つ文書の検索結果だけ得たい場合
		if ($query->{dids}) {
		    for (my $i = 0; $i < $docs_size; $i++) {
			my $did = sprintf("%09d", $docs->[$i]{did});
			next unless (exists $query->{dids}{$did});

			$docs->[$i]{url} = $URL_DBs{$did};
			$docs->[$i]{title} = $TITLE_DBs{$did};
			$docs->[$i]{title} = 'no title.' unless ($docs->[$i]{title});

			push(@{$ret}, $docs->[$i]);
		    }
		} else {
		    my $results = $query->{results};
		    # my $results = ($query->{accuracy}) ? $query->{results} * $query->{accuracy} : $query->{results};
		    $results += $query->{start};
		    $results = $docs_size if ($docs_size < $results);

		    # タイトルDBがない場合はタイトルDBをひく操作をしない
		    my $max_rank_of_getting_title_and_url = (scalar(keys %TITLE_DBs) > 0) ? $results * $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE : 0;
		    print $query->{results} . "=ret " . $query->{accuracy} . "=acc " . $results . " * " . $WEIGHT_OF_MAX_RANK_FOR_SETTING_URL_AND_TITLE . " = " . $max_rank_of_getting_title_and_url . "*\n" if ($opt{debug});
		    my $size = 0;
		    for (my $i = 0; $size < $results && $i < $results; $i++) {
			my $did;
			if ($CONFIG->{IS_NICT_MODE}) {
			    $did = sprintf("%06d", $docs->[$i]{did});
			    $did = $tid2sid{$did};
			    $docs->[$i]{did} = $did;
			} else {
			    $did = sprintf("%09d", $docs->[$i]{did});
			}

			if (exists $STOP_PAGE_LIST{$did}) {
			    $hitcount--;
			} else {
			    if ($i < $max_rank_of_getting_title_and_url) {
				$docs->[$i]{url} = $URL_DBs{$did} unless ($docs->[$i]{url});
				$docs->[$i]{title} = $TITLE_DBs{$did};
				$docs->[$i]{title} = 'no title.' unless ($docs->[$i]{title});

				print decode('utf8', $docs->[$i]{title} . "=title, " . $docs->[$i]{url} . "=url\n") if ($opt{verbose});
			    }
			    push(@{$ret}, $docs->[$i]);
			    $size++;
			}
		    }
		}

		print $new_socket encode_base64($hitcount, "") , "\n";
		print $new_socket "END_OF_HITCOUNT\n";

		if ($opt{verbose}) {
		    print Dumper($ret) . "\n";
		    print "-----\n";
		}

		print $new_socket encode_base64(Storable::nfreeze($ret), "") , "\n";
		print $new_socket "END\n";
	    }
	    $new_socket->close();
	    exit;
	}
    }
}
