package SearchEngine;

# 各検索サーバーとindex.cgiおよびapi.cgiを結ぶブリッジ

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Storable;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use Time::HiRes;
use CDB_File;
use Configure;
use QueryParser;
use State;
use Logger;
use Tsubaki::CacheManager;

my $CONFIG = Configure::get_instance();

# コンストラクタ
# 接続先ホスト、ポート番号
sub new {
    my($class, $syngraph) = @_;
    my $this = {hosts => []};

    my $servers;
    if ($syngraph > 0) {
	$servers = $CONFIG->{SEARCH_SERVERS_FOR_SYNGRAPH};
    } else {
	$servers = $CONFIG->{SEARCH_SERVERS};
    }
    foreach my $s (@$servers) {
	push(@{$this->{hosts}}, {name => $s->{name}, port => $s->{port}});
    }

    bless $this;
}

sub init {
    my ($this, $dir) = @_;
    opendir(DIR, $dir) or die;
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	next if ($cdbf =~ /keymap/);

	my $fp = "$dir/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	if (index($cdbf, 'dpnd.cdb') > -1) {
	    push(@{$this->{DF_DPND_DBs}}, \%dfdb);
	} elsif (index($cdbf, 'word.cdb') > -1) {
	    push(@{$this->{DF_WORD_DBs}}, \%dfdb);
	}
    }
    closedir(DIR);
}

# デストラクタ
sub DESTROY {}

# 呼出用検索インターフェイス
sub search {
    my ($this, $query, $logger, $opt) = @_;

    my $cache = new Tsubaki::CacheManager();
    my $result = $cache->load($query);
    my $status;

    if ($result && !$opt->{disable_cache}) {
	$logger->setTimeAs('search', '%.3f');
	$logger->setParameterAs('IS_CACHE', 1);
	$status = 'cache';
    } else {
	# 混雑していない or スケジューリング機能を用いない場合は検索サーバーに対してクエリを投げる
	my $state = new State();
	if ($CONFIG->{DISABLE_REQUEST_SCHEDULING} || $state->checkIn()) {
	    $result = $this->broadcastSearch($query, $logger, $opt);

	    $cache->save($query, $result) unless ($opt->{disable_cache});
	    $logger->setParameterAs('IS_CACHE', 0);
	    $state->checkOut();
	    $status = 'search';
	} else {
	    # 混雑していて検索できなかった
	    $status = 'busy';
	}
    }

    return ($result->{hitcount}, $result->{hitpages}, $status);
}

sub get_DF {
    my ($this, $k) = @_;
    my $k_utf8 = encode('utf8', $k);
    my $gdf = -1;
    my $DFDBs = (index($k, '->') > 0) ? $this->{DF_DPND_DBs} : $this->{DF_WORD_DBs};
    foreach my $dfdb (@{$DFDBs}) {
 	if (exists($dfdb->{$k_utf8})) {
 	    $gdf = $dfdb->{$k_utf8};
 	    last;
 	}
    }
    return $gdf;
}


sub fisher_yates_shuffle {
    my ($array) = @_;

    my $i;
    for ($i = @$array; --$i;) {
	my $j = int rand ($i+1);
	next if ($i == $j);
	@$array[$i,$j] = @$array[$j,$i];
    }
}


# 実際に検索を行うメソッド
sub broadcastSearch {
    my($this, $query, $logger, $opt) = @_;

    $query->{sort_by_year} = $opt->{sort_by_year};
    # $opt->{debug} = 1;
    # $logger->clearTimer();

    # 検索クエリの送信
    my $selecter = IO::Select->new();
    # アクセスが集中しないようにランダムに並び変える
    &fisher_yates_shuffle($this->{hosts});
    for (my $i = 0; $i < scalar(@{$this->{hosts}}); $i++) {
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $this->{hosts}->[$i]->{name},
	    PeerPort => $this->{hosts}->[$i]->{port} + (($opt->{reference}) ? 1 : 0),
	    Proto    => 'tcp' );

	$query->{logger} = new Logger();
	print "send query to " . $this->{hosts}[$i]{name} . ":" . $this->{hosts}[$i]{port} . "<BR>\n" if ($opt->{debug});
	$selecter->add($socket) or die "Cannot connect to the server (host=$this->{hosts}->[$i]->{name}, port=$this->{hosts}->[$i]->{port})";
	
 	# 検索クエリの送信
 	print $socket encode_base64(Storable::nfreeze($query), "") . "\n";
	print $socket "EOQ\n";

	# qid2dfの送信
 	print $socket encode_base64(Storable::nfreeze($query->{qid2df}), "") . "\n";
	print $socket "END\n";

	$socket->flush();
    }
    $logger->setTimeAs('send_query_to_server', '%.3f');


    # 検索結果の受信
    my @results = ();
    my $total_hitcount = 0;
    my $num_of_sockets = scalar(@{$this->{hosts}});
    my %logbuf = ();
    my %host2log = ();
    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}) {
	    my $buff = undef;
	    # ホスト情報の取得
	    while (<$socket>) {
		last if ($_ eq "END_OF_HOST\n");
		$buff .= $_;
	    }
	    my $hostinfo;
	    $hostinfo = Storable::thaw(decode_base64($buff)) if (defined($buff));


	    # ログ情報の取得
	    $buff = undef;
	    while (<$socket>) {
		last if ($_ eq "END_OF_LOGGER\n");
		$buff .= $_;
	    }

	    my $slave_logger = undef;
	    if (defined $buff) {
		$slave_logger = Storable::thaw(decode_base64($buff));
		$slave_logger->setTimeAs('transfer_time_from', '%.3f');

		# 検索に要した全時間
		$slave_logger->setParameterAs('total_time', sprintf ("%.3f",
								     $slave_logger->getParameter('transfer_time_to') +
								     $slave_logger->getParameter('normal_search') +
								     $slave_logger->getParameter('logical_condition') +
								     $slave_logger->getParameter('near_condition') +
								     $slave_logger->getParameter('merge_dids') +
								     $slave_logger->getParameter('document_scoring') +
								     $slave_logger->getParameter('transfer_time_from')));


		foreach my $k ($slave_logger->keys()) {
		    my $v = $slave_logger->getParameter($k);
		    $logbuf{$k} += $v;

		    if (exists $logbuf{"max_$k"}) {
			$logbuf{"max_$k"} = $v if ($logbuf{"max_$k"} < $v);
		    } else {
			$logbuf{"max_$k"} = $v;
		    }

		    if (exists $logbuf{"min_$k"}) {
			$logbuf{"min_$k"} = $v if ($logbuf{"mix_$k"} > $v);
		    } else {
			$logbuf{"min_$k"} = $v;
		    }
		}
	    } else {
		print "<EM>検索スレーブ側のログデータを受信できませんでした。</EM><BR>\n" if ($opt->{debug});
	    }


	    # ヒットカウントの取得
	    $buff = undef;
	    while (<$socket>) {
		last if ($_ eq "END_OF_HITCOUNT\n");
		$buff .= $_;
	    }
	    my $num = -1;
	    if (defined($buff)) {
		$num = decode_base64($buff);
		$total_hitcount += $num;
	    }


	    # 検索により得られた文書情報の取得
	    my $docs;
	    unless ($query->{only_hitcount}) {
		$buff = undef;
		while (<$socket>) {
		    last if ($_ eq "END\n");
		    $buff .= $_;
		}
		if (defined($buff)) {
		    $docs = Storable::thaw(decode_base64($buff));
		    my $host = $hostinfo->{name};
		    print "$host returned. ($num)<BR>\n" if ($opt->{debug});
		    push(@results, $docs);
		}
	    }

	    if ($slave_logger) {
		$slave_logger->setParameterAs('data_size', sprintf ("%d", length($buff)));
		$slave_logger->setParameterAs('hitcount', sprintf ("%d", $num));
		$slave_logger->setParameterAs('port', sprintf ("%d", $hostinfo->{port}));

		# ホストごとのログを保存
		push(@{$host2log{$hostinfo->{name}}}, $slave_logger);
	    }

	    # ソケットの後処理
	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }
    $logger->setTimeAs('get_result_from_server', '%.3f');
    if ($opt->{debug}) {
	print "finish to harvest search results (" . $logger->getParameter('get_result_from_server') . " sec.)\n";
    }

    # 検索スレーブサーバー側でのログをセット
    my $size = scalar(@results);
    foreach my $k (keys %logbuf) {
	if ($k =~ /^(max|min)/) {
	    $logger->setParameterAs($k, sprintf ("%.3f", $logbuf{$k}));
	} else {
	    $logger->setParameterAs($k, sprintf ("%.3f", $logbuf{$k} / $size)) if ($size > 0);
	}
    }

    # 検索に要した時間をロギング
    $logger->setParameterAs('search', $logger->getParameter('send_query_to_server') + $logger->getParameter('get_result_from_server'));


    # 各サーバーからの返されたログを保持
    $logger->setParameterAs('host2log', \%host2log);


    # 受信した結果を揃える
    @results = sort {$b->[0]{score_total} <=> $a->[0]{score_total}} @results;
    return {hitcount => $total_hitcount, hitpages => \@results};
}

sub decodeResult {
    my($result_str) = @_;
    my @result_ary;
    foreach (split(/\n/, $result_str)){
	my($did,$score) = split(/,/, $_);
	push(@result_ary, {did => $did, score => $score});
    }
    return \@result_ary;
}

1;
