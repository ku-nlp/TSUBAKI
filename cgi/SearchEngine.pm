package SearchEngine;

# 各検索サーバーとindex.cgiおよびapi.cgiを結ぶブリッジ

my $TOOL_HOME='/home/skeiji/local/bin';

use strict;
use Encode;
use utf8;
use IO::Socket;
use IO::Select;
use Time::HiRes;
use CDB_File;

# コンストラクタ
# 接続先ホスト、ポート番号
sub new {
    my($d, $hosts, $port, $type) = @_;
    my $this = {HOSTS => $hosts, PORT => $port, TYPE => $type};

    bless $this;
}

# デストラクタ
sub DESTROY {}

## 呼出用検索インターフェイス
sub search {
    my ($this, $query, $opts) = @_;

    ## 検索サーバーに対してクエリを投げる
    my $results = $this->broadcastSearch($query, $opts);
    my $hitcount = pop(@{$results});
    
    return ($hitcount, $results, $opts);
}

# 実際に検索を行うメソッド
sub broadcastSearch {
    my($this, $query, $opts) = @_;

    my $search_qs_str;
    my $phrase_qs_str;
    foreach my $q (@{$query}){
	my $qs_str = undef;
	foreach my $reps (sort {$a->[0]->{pos} <=> $b->[0]->{pos}} @{$q->{words}}){
	    foreach my $k (@{$reps}){
		next if($k->{isContentWord} < 1 && $q->{near} < 0);
		$qs_str .= "$k->{rawstring}_$k->{gdf}+";
	    }
	    chop($qs_str);
	    unless ($qs_str =~ /@$/ &&
		    $qs_str eq ''){
		$qs_str .= "@";
	    }
	}

	foreach my $reps (sort {$a->[0]->{pos} <=> $b->[0]->{pos}} @{$q->{dpnds}}){
	    foreach my $k (@{$reps}){
		$qs_str .= "$k->{rawstring}_$k->{gdf}+";
	    }
	    chop($qs_str);
	    unless ($qs_str =~ /@$/ &&
		    $qs_str eq ''){
		$qs_str .= "@";
	    }
	}
	
	chop($qs_str);
	$search_qs_str .= $qs_str . "#";
	$search_qs_str .= $q->{near};
	$search_qs_str .= ";";
    }

    chop($search_qs_str);

    my $selecter = IO::Select->new;
    my $sleeptime = 0;
    $sleeptime = int(rand(90)) + 30 if($this->{TYPE} eq 'API');
    $search_qs_str = encode('utf8', $search_qs_str);
    for(my $i = 0; $i < scalar(@{$this->{HOSTS}}); $i++){
	my $host = $this->{HOSTS}->[$i];

	my $socket = IO::Socket::INET->new(PeerAddr => $host,
					   PeerPort => $this->{PORT},
					   Proto    => 'tcp',
					   );

	my $topN = $opts->{start} + $opts->{results};
#	print "$i :: $host $sleeptime,SEARCH,$search_qs_str,$opts->{ranking_method},$opts->{logical_operator},$opts->{dpnd}, $opts->{force_dpnd}, $topN, $opts->{near}, $opts->{only_hitcount}\n <br>";

	$selecter->add($socket) or die "$host に接続できませんでした。 $!\n";

	# 文字列を送信
#	print "$sleeptime,SEARCH,$search_qs_str,$opts->{ranking_method},$opts->{logical_operator},$opts->{dpnd}, $opts->{force_dpnd}, $topN, $opts->{near}, $opts->{only_hitcount}<br>\n";
	print $socket "$sleeptime,SEARCH,$search_qs_str,$opts->{ranking_method},$opts->{logical_operator},$opts->{dpnd}, $opts->{force_dpnd}, $topN, $opts->{near}, $opts->{only_hitcount}\n";
	$socket->flush();
    }
    
    ## 検索サーバーより検索結果を受信
    my @results;
    my $hitcount = 0;
    my $num_of_sockets = scalar(@{$this->{HOSTS}});
    while($num_of_sockets > 0){
	my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}){
	    my $buff = <$socket>;
	    chop($buff);
	    $hitcount += $buff;

	    $buff = <$socket>;
	    $buff =~ s/\[RET\]/\n/g;
	    push(@results, &decodeResult($buff));
		
	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;
	}
    }
    push(@results,$hitcount);
    return \@results;
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
