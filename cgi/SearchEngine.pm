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
use Cache;


# コンストラクタ
# 接続先ホスト、ポート番号
sub new {
    my($class, $syngraph) = @_;
    my $this = {hosts => []};

    my $CONFIG = Configure::get_instance();

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
    my ($this, $query, $logger) = @_;

    my $cache = new Cache();
    my $result = $cache->load($query);
    if ($result) {
	$logger->setTimeAs('search', '%.3f');
	$logger->setParameterAs('IS_CACHE', 1);
    } else {
	# 検索サーバーに対してクエリを投げる
	$result = $this->broadcastSearch($query, $logger);
	$cache->save($query, $result);
	$logger->setParameterAs('IS_CACHE', 0);
    }

    return ($result->{hitcount}, $result->{hitpages});
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

# 実際に検索を行うメソッド
sub broadcastSearch {
    my($this, $query, $logger) = @_;

    # $logger->clearTimer();

    # 検索クエリの送信
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@{$this->{hosts}}); $i++) {
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $this->{hosts}->[$i]->{name},
	    PeerPort => $this->{hosts}->[$i]->{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die "Cannot connect to the server $this->{hosts}->[$i]->{name}:$this->{hotst}->[$i]->{port}. $!\n";
	
 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";
	
	# qid2dfの送信
 	print $socket encode_base64(Storable::freeze($query->{qid2df}), "") . "\n";
	print $socket "END\n";
	
	$socket->flush();
    }
    $logger->setTimeAs('send_query_to_server', '%.3f');    


    # 検索結果の受信
    my @results = ();
    my $total_hitcount = 0;
    my $num_of_sockets = scalar(@{$this->{hosts}});
    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}) {
	    my $buff = undef;
	    while (<$socket>) {
		last if ($_ eq "END_OF_HITCOUNT\n");
		$buff .= $_;
	    }
	    $total_hitcount += decode_base64($buff) if (defined($buff));

	    my $docs;
	    unless ($query->{only_hitcount}) {
		$buff = undef; 
		while (<$socket>) {
		    last if ($_ eq "END\n");
		    $buff .= $_;
		}
		if (defined($buff)) {
		    $docs = Storable::thaw(decode_base64($buff));
		    push(@results, $docs);
		}
	    }

	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }
    $logger->setTimeAs('get_result_from_server', '%.3f');
    
    # 検索に要した時間をロギング
    $logger->setParameterAs('search', $logger->getParameter('send_query_to_server') + $logger->getParameter('get_result_from_server'));

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
