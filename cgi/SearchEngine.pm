package SearchEngine;

# 各検索サーバーとindex.cgiおよびapi.cgiを結ぶブリッジ

use strict;
use utf8;
use Encode;
use Storable;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use Configure;
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

# 配列内の変数をランダムに並び変える
sub fisher_yates_shuffle {
    my ($array) = @_;

    my $i;
    for ($i = @$array; --$i;) {
	my $j = int rand ($i+1);
	next if ($i == $j);
	@$array[$i,$j] = @$array[$j,$i];
    }
}

# 検索クエリの送信
sub send_query_to_slave_servers {
    my($this, $selecter, $query, $logger, $opt) = @_;

    # アクセスが集中しないようにランダムに並び変える
    &fisher_yates_shuffle($this->{hosts});

    for (my $i = 0; $i < scalar(@{$this->{hosts}}); $i++) {
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $this->{hosts}->[$i]->{name},
	    PeerPort => $this->{hosts}->[$i]->{port} + (($opt->{reference}) ? 1 : 0),
	    Proto    => 'tcp' );

	print "send query to " . $this->{hosts}[$i]{name} . ":" . $this->{hosts}[$i]{port} . "<BR>\n" if ($opt->{debug} > 1);
	$selecter->add($socket) or die "Cannot connect to the server (host=$this->{hosts}->[$i]->{name}, port=$this->{hosts}->[$i]->{port})";

 	# クエリの送信
 	print $socket $query . "\n";
	$socket->flush();
    }
    $logger->setTimeAs('send_query_to_server', '%.3f');
}

# 検索結果の受信
sub recieve_result_from_slave_servers {
    my($this, $selecter, $query, $logger, $opt) = @_;

    my @results = ();
    my $total_hitcount = 0;
    my $num_of_sockets = scalar(@{$this->{hosts}});
    my %logbuf = ();
    my %host2log = ();

    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);

	foreach my $socket (@{$readable_sockets}) {
	    my ($hitcount, $result_docs) = $this->parse_recieved_data($socket, $query, \%host2log, \%logbuf, $opt);

	    $total_hitcount += $hitcount;
	    push (@results, @$result_docs);

	    # ソケットの後処理
	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }

    return ($total_hitcount, \@results, \%host2log, \%logbuf);
}

# 受信したデータのパース
sub parse_recieved_data {
    my ($this, $socket, $query, $host2log, $logbuf, $opt) = @_;

    if ($CONFIG->{IS_CPP_MODE}) {
	return $this->parse_recieved_data_for_cpp($socket, $query, $host2log, $logbuf, $opt);
    } else {
	return $this->parse_recieved_data_for_perl($socket, $query, $host2log, $logbuf, $opt);
    }
}

# 受信したデータのパース(C++用)
sub parse_recieved_data_for_cpp {
    my ($this, $socket, $query, $host2log, $logbuf, $opt) = @_;

    require Time::HiRes;

    my @t_buf = ();
    my @results;
    my ($tbuf, $buff, $hitcount, $recieved_data, $slave_server_side_total, $hostname, $port, $search_time, $score_time, $sort_time);
    while (<$socket>) {
	chop;

	if ($_ =~ /hitcount (\d+)/) {
	    $hitcount = $1;
	    push (@t_buf, sprintf ("hitc=%d", $hitcount));
	} elsif ($_ =~ /COMEIN (\d+)/) {
	    $tbuf = $1;
	} elsif ($_ =~ /S_EXP_PARSE (.+)/) {
	    push (@t_buf, sprintf ("sexp_parse=%s", $1 - $tbuf));
	    $tbuf = $1;
	} elsif ($_ =~ /SEARCH_TIME (.+)/) {
	    $search_time = $1;
	} elsif ($_ =~ /SCORE_TIME (.+) (.+)$/) {
	    $score_time = $1 + $2;
	} elsif ($_ =~ /SORT_TIME (.+)$/) {
	    $sort_time = $1;
	} elsif ($_ =~ /MERGE_AND_OR (\d+)/) {
	    push (@t_buf, sprintf ("merge_and_or=%d", $1 - $tbuf));
	    $tbuf = $1;
	} elsif ($_ =~ /WALK_AND_OR_1 (\d+)/) {
	    push (@t_buf, sprintf ("walk_and_or_1=%d", $1 - $tbuf));
	    $tbuf = $1;
	} elsif ($_ =~ /WALK_AND_OR_2 (\d+)/) {
	    push (@t_buf, sprintf ("walk_and_or_2=%d", $1 - $tbuf));
	    $tbuf = $1;
	} elsif ($_ =~ /SORT (\d+)/) {
	    push (@t_buf, sprintf ("sort=%d", $1 - $tbuf));
	    $tbuf = $1;
	} elsif ($_ =~ /HOSTNAME (.+?) (\d+)$/) {
	    $hostname = $1;
	    $port = $2;
	} elsif ($_ =~ /LEAVE (.+?) (.+)/) {
	    $slave_server_side_total = $1;
	    my $leave_time = $2;
	    push (@t_buf, sprintf ("slave_server_side_total=%.5f", $slave_server_side_total));
	    last;
	} else {
	    $recieved_data .= $_;

	    my ($sid, $tid, $score, $start, $end, $title, $url, $score) = split (/ /, $_);
	    my $doc;
	    $doc->{did} = $sid;
	    $doc->{start} = $start;
	    $doc->{end} = $end;
	    $doc->{title} = $title;
	    $doc->{url} = $url;
	    $doc->{score_total} = $score;

	    push (@results, $doc);
	}
    }

    my $slave_logger = new Logger();
#   $slave_logger->setParameterAs('data_size', sprintf ("%d", length($buff)));
    $slave_logger->setParameterAs('normal_search', sprintf ("%.3f", $search_time));
    $slave_logger->setParameterAs('hitcount', sprintf ("%d", $hitcount));
    $slave_logger->setParameterAs('port', sprintf ("%d", $port));
    $slave_logger->setParameterAs('total_time', sprintf ("%.3f", $slave_server_side_total));
    $slave_logger->setParameterAs('document_scoring', sprintf ("%.3f", $score_time));
    $slave_logger->setParameterAs('merge_dids', sprintf ("%.3f", $sort_time));

    # ホストごとのログを保存
    push (@{$host2log->{$hostname}}, $slave_logger);

    return ($hitcount, [\@results]);
}


# 受信したデータのパース(perl用)
sub parse_recieved_data_for_perl {
    my ($this, $socket, $query, $host2log, $logbuf, $opt) = @_;

    my $buff = undef;
    # ホスト情報の取得
    while (<$socket>) {
	last if ($_ eq "END_OF_HOST\n");
	$buff .= $_;
    }
    my $hostinfo = Storable::thaw(decode_base64($buff)) if (defined($buff));


    # ログ情報の取得
    $buff = undef;
    while (<$socket>) {
	last if ($_ eq "END_OF_LOGGER\n");
	$buff .= $_;
    }

    my $slave_logger = undef;
    unless (defined $buff) {
	print "<EM>検索スレーブ側のログデータを受信できませんでした。</EM><BR>\n" if ($opt->{debug});
    } else {
	$slave_logger = Storable::thaw(decode_base64($buff));
	$slave_logger->setTimeAs('transfer_time_from', '%.3f');

	# 検索に要した全時間
	my $total_time = $slave_logger->getParameter('transfer_time_to') + $slave_logger->getParameter('normal_search') + $slave_logger->getParameter('logical_condition') + $slave_logger->getParameter('near_condition')
	    + $slave_logger->getParameter('merge_dids') + $slave_logger->getParameter('document_scoring') + $slave_logger->getParameter('transfer_time_from');
	$slave_logger->setParameterAs('total_time', sprintf ("%.3f", $total_time));

	# 各値の最大値、最小値を取得
	foreach my $k ($slave_logger->keys()) {
	    my $v = $slave_logger->getParameter($k);
	    $logbuf->{$k} += $v;

	    if (exists $logbuf->{"max_$k"}) {
		$logbuf->{"max_$k"} = $v if ($logbuf->{"max_$k"} < $v);
	    } else {
		$logbuf->{"max_$k"} = $v;
	    }

	    if (exists $logbuf->{"min_$k"}) {
		$logbuf->{"min_$k"} = $v if ($logbuf->{"mix_$k"} > $v);
	    } else {
		$logbuf->{"min_$k"} = $v;
	    }
	}
    }


    # ヒットカウントの取得
    $buff = undef;
    while (<$socket>) {
	last if ($_ eq "END_OF_HITCOUNT\n");
	$buff .= $_;
    }
    my $hitcount = (defined($buff)) ? decode_base64($buff) : 0;


    # 検索により得られた文書情報の取得
    my @results;
    unless ($query->{only_hitcount}) {
	$buff = undef;
	while (<$socket>) {
	    last if ($_ eq "END\n");
	    $buff .= $_;
	}
	push (@results, Storable::thaw(decode_base64($buff))) if (defined($buff));
	print "$hostinfo->{name} returned. ($hitcount)<BR>\n" if ($opt->{debug} > 1);
    }

    if ($slave_logger) {
	$slave_logger->setParameterAs('data_size', sprintf ("%d", length($buff)));
	$slave_logger->setParameterAs('hitcount', sprintf ("%d", $hitcount));
	$slave_logger->setParameterAs('port', sprintf ("%d", $hostinfo->{port}));

	# ホストごとのログを保存
	push (@{$host2log->{$hostinfo->{name}}}, $slave_logger);
    }

    return ($hitcount, \@results);
}

# 実際に検索を行うメソッド
sub broadcastSearch {
    my($this, $query, $logger, $opt) = @_;

    $query->{sort_by_year} = $opt->{sort_by_year};

    ##################
    # 検索クエリの送信
    ##################
    my $_logger = new Logger();
    my $selecter = IO::Select->new();
    # 実際にサーバーに送信するデータ
    my $query_dat;
    if ($CONFIG->{IS_CPP_MODE}) {
	$query_dat = $query->{s_exp};
	$query_dat =~ s/\n//g;
    } else {
	$query->{logger} = new Logger();
	my $_query = encode_base64(Storable::nfreeze($query), "") . "\n";
	$_query .= "EOQ\n";
 	$_query .= encode_base64(Storable::nfreeze($query->{qid2df}), "") . "\n";
	$_query .= "END\n";
	$query_dat = $_query;
    }
    $this->send_query_to_slave_servers($selecter, $query_dat, $logger, $opt);


    ##################
    # 検索クエリの受信
    ##################
    my ($total_hitcount, $_results, $host2log, $logbuf) = $this->recieve_result_from_slave_servers($selecter, $query, $logger, $opt);


    ##########
    # ロギング
    ##########
    $_logger->setTimeAs('get_result_from_server', '%.3f');
#    print "slave_server_access " . $_logger->getParameter('get_result_from_server') . "<BR>\n";
#    print "finish to harvest search results (" . $logger->getParameter('get_result_from_server') . " sec.)\n" if ($opt->{debug} > 1);

    # 検索スレーブサーバー側でのログを保存
    my $size = scalar(@$_results);
    foreach my $k (keys %$logbuf) {
	if ($k =~ /^(max|min)/) {
	    $logger->setParameterAs($k, sprintf ("%.3f", $logbuf->{$k}));
	} else {
	    $logger->setParameterAs($k, sprintf ("%.3f", $logbuf->{$k} / $size)) if ($size > 0);
	}
    }

    # 検索に要した時間をロギング
    $logger->setParameterAs('search', $logger->getParameter('send_query_to_server') + $logger->getParameter('get_result_from_server'));

    # 各サーバーからの返されたログを保持
    $logger->setParameterAs('host2log', $host2log);


    # 受信した結果を揃える
    my @results = sort {$b->[0]{score_total} <=> $a->[0]{score_total}} @$_results;
    return {hitcount => $total_hitcount, hitpages => \@results};
}

1;
