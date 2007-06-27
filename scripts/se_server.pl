#!/usr/local/bin/perl

use strict;
use IO::Socket;
use Retrieve;
use Indexer qw(makeIndexfromKnpResult makeIndexfromJumanResult);
use Encode qw(from_to encode decode);
use URI::Escape;
use Storable qw(store retrieve);
use utf8;
use CDB_File;
use Data::Dumper;
# use Devel::Size qw(total_size);
use Getopt::Long;



my (%opt); GetOptions(\%opt, 'dfdbdir=s', 'idxdir=s', 'port=s', 'skip_pos', 'debug');

# host名を得る
my $host = `hostname`; chop($host);


binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");

my $TOOL_HOME = '/home/skeiji/local/bin';

##############################################################
# 単語、係り受けそれぞれについて文書頻度データベースをロード #
##############################################################
print STDERR "$host> loading df database...\n";

my $ret_word = new Retrieve2($opt{idxdir}, 'word', $opt{skip_pos});
my $ret_dpnd = new Retrieve2($opt{idxdir}, 'dpnd', $opt{skip_pos});

print STDERR "$host> done.\n";
print STDERR "$host> port=$opt{port}\n";
print STDERR "$host> index_dir=$opt{idxdir}\n";
print STDERR "$host> ready!\n";

# my $dlength_fp = '/data/doc_length.cdb';
# ## 文書長DBの保持
# print STDERR "$host> loading doc_length database ($dlength_fp)...\n";
# tie my %DOC_LENGTH, 'CDB_File', $dlength_fp or die;
# print STDERR "$host> done.\n";


######################################################################
# 全文書数
#our $N = 48420000;
my $N = 51000000;
# 平均文書長
my $AVE_DOC_LENGTH = 871.925373263118;
# my $AVE_DOC_LENGTH = 483.852649424932;
######################################################################

my @DOC_LENGTH_DBs = ();
opendir(DIR, $opt{idxdir});
foreach my $dbf (readdir(DIR)) {
    next unless ($dbf =~ /doc_length.bin/);

    my $fp = "$opt{idxdir}/$dbf";
#    tie my %dlength_db, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
#    push(@DOC_LENGTH_DBs, \%dlength_db);
    my $dlength_db = retrieve($fp);
    push(@DOC_LENGTH_DBs, $dlength_db);
}
closedir(DIR);

# foreach my $cdb (@DOC_LENGTH_DBs) {
#     untie %{$cdb};
# }


&main();

sub main{
    my $listening_socket = IO::Socket::INET->new(LocalPort => $opt{port},
						 Listen    => SOMAXCONN,
						 Proto     => 'tcp',
						 Reuse     => 1,
	);

    unless($listening_socket){
	my $host = `hostname`;
	chop($host);
	die "listen\@{$host} できませんでした。 $!\n";
    }

    ############################
    # 検索クエリが来るまで待つ #
    ############################
    my $current_jobs = 0;
    while(1){
	my $new_socket = $listening_socket->accept();
	my $client_sockaddr = $new_socket->peername();
	my($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
	my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
	my $client_ip = inet_ntoa($client_iaddr);
	
	select($new_socket); $|=1; select(STDOUT);

	if(my $pid = fork()){
	    $new_socket->close();
	    next;
	}else{
	    my @load_ave = split(/ /, `uptime`);
	    my @free_cmd = split(/ +/, `free | head -2 | tail -1`);
	    chop($load_ave[14]);
	    if($load_ave[14] > 3.0 || $free_cmd[3] < 0){
#		my $sleeptime = int(rand(90)) + 30;
		my $sleeptime = int(rand(15)) + 5;
		print STDERR "$host> sleep $sleeptime sec. since the server is crowded (load=$load_ave[14],mem=$free_cmd[3])\n";
#		sleep($sleeptime);

		@load_ave = split(/ /, `uptime`);
		@free_cmd = split(/ +/, `free | head -2 | tail -1`);
		chop($load_ave[14]);
	    }

	    $current_jobs++;
	    print STDERR "$host> the search process is forked.\n";
	    # print "接続(port=${PORT}): $client_hostname(${client_ip}) ポート ${client_port}\n";
	    select($new_socket); $|=1; select(STDOUT);

	    # 検索クエリの解析
	    my $search_q = decode('utf8', <$new_socket>);
	    chomp($search_q);
	    my($sleeptime,$action,@opts) = split(/,/,$search_q);

	    if($sleeptime > 0){
#		print STDERR "$host> sleep $sleeptime seconds. [API ACCESS]\n";
#		sleep($sleeptime);
	    }

	    if($action eq "SEARCH"){
		my $d_scores = &search_wo_hash(@opts);
		my $required_results = $opts[5];

		# 検索結果の送信
		&returnSearchResults($new_socket, $d_scores, $required_results);
	    }elsif($action eq "GET"){
		&get(@opts);
	    }
	    $new_socket->close();
	    $current_jobs--;
	    print STDERR ">> $search_q\n";
	    exit;
	}
    }
}

sub get{
    my($fid,$new_socket) = @_;
    $fid =~ /(....)\d+/;
    my $dir = 'x' . $1 . '_idx';
#   my $filepath = "$opt{idxdir}/$dir/$fid.idx";
    my $filepath = "/data/knpidxes/$dir/$fid.idx";
    my $buff = '';
    unless(-e $filepath){
	print $new_socket "Not found.\n";
    }else{
	print STDERR "$filepath\n";
	open(READER, '<:utf8', $filepath);
	while(<READER>){
	    chomp($_);
	    $buff .= (encode('utf8',$_) . ',');
	}
	chop($buff);
	print $new_socket "$buff\n";
	close(READER);
    }
    close($new_socket);
}

sub parseInput{
    my($query_str) = @_;

    my $qid = 0;
    my %qid2gdf;
    my @queries;

    # クエリごとに区切る
    foreach my $q_with_near (split(/;/, $query_str)){
	# クエリをnearと単語に区切る
	my ($q, $near) = split(/#/, $q_with_near);
	my %query = ();
	$query{near} = $near;

	# クエリを単語に区切る
	foreach my $kwd (split(/@/, $q)){
	    if(index($kwd, "->") > 0){
		my @reps;
		# 代表表記_文書頻度ごとに区切る
		foreach my $rep (split(/\+/, $kwd)){
		    my ($e, $gdf) = split('_', $rep);
		    $qid2gdf{$qid} = $gdf;

		    push(@reps, {keyword => $e, id => $qid++, gdf => $gdf});
		}
		push(@{$query{DPND}}, \@reps);
	    }else{
		my @reps;
		# 代表表記ごとに区切る
		foreach my $rep (split(/\+/, $kwd)){
		    my ($e, $gdf) = split('_', $rep);
		    $qid2gdf{$qid} = $gdf;

		    push(@reps, {keyword => $e, id => $qid++, gdf => $gdf});
		}
		push(@{$query{WORD}}, \@reps);
	    }
	}
	push(@queries, \%query);
    }

    return (\@queries, \%qid2gdf);
}
    
sub search_wo_hash {
    my($input,$ranking_method,$logical_cond,$sf_level,$dpnd_condition,$required_results,$near, $only_hitcount) = @_;
    # サーバーから送信されてきたユーザのクエリを単語/係り受けに分類
    my($queries, $qid2gdf) = &parseInput($input);

    my @search_results_word;
    my @search_results_dpnd;

    print STDERR "$host> DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG\n";
    foreach my $query (@{$queries}){
	my %dbuff = ();
	my $registFlag = 1;
	foreach my $type (keys %{$query}){
	    next if($type eq 'near');
	    
	    my @search_result_word = ();
	    my @search_result_dpnd = ();
	    my $w_lists = $query->{$type};
	    foreach my $ws (@{$w_lists}){
		## ログを出力
		foreach my $w (@{$ws}){
		    my $qid = $w->{id};
		    my $kwd = $w->{keyword};
		    my $gdf = $w->{gdf};
		    print STDERR "$host> $type :: qid=$qid keyword=$kwd gdf=$gdf\n";
		}
		
		## 代表表記／SynGraph により複数個の索引に分割された場合の処理 (かんこう -> 観光 OR 刊行 OR 敢行 OR 感光 を検索する)
		my $result;
		if($type eq 'WORD'){
		    if($query->{near} > 0){
			$result = $ret_word->search_wo_hash($ws, \%dbuff, $registFlag, 0);
		    }else{
			## 通常の検索
			if ($near < 1) {
			    $result = $ret_word->search_wo_hash($ws, undef, undef, 1);
			} else {
			    ## 近接検索
			    $result = $ret_word->search_wo_hash($ws, undef, undef, 0);
			}
		    }
		}else{
		    ## 係受けを含む文書の検索
		    print "$ws\n";
		    $result = $ret_dpnd->search_wo_hash($ws, undef, undef, 1);
		}
		
		## OR をとる
		my $merged_result = [];
		foreach my $ret (@{$result}){
		    foreach my $r (@{$ret}){
			push(@{$merged_result}, $r);
		    }
		}
		
		$registFlag = 0 if($registFlag > 0); 
		
		## 各検索語について検索された結果を納めた配列に push
		@{$merged_result} = sort {$a->{did} <=> $b->{did}} @{$merged_result};
		if($type eq 'WORD'){
		    push(@search_result_word, $merged_result);
		}else{
		    push(@search_result_dpnd, $merged_result);
		}
	    }
	    
	    if ($type eq 'WORD' && $query->{near} > 0) {
		## フレーズ検索
		print STDERR "phrasal search starting...\n";
		my $tmp = &intersect_wo_hash(\@search_result_word, $query->{near});
		foreach my $r (@{$tmp}) {
		    push(@search_results_word, $r);
		}
	    } elsif ($type eq 'WORD' && $near > 0) {
		## 近接検索
		print STDERR "near search starting...\n";
		my $tmp = &intersect_wo_hash(\@search_result_word, $near);
		foreach my $r (@{$tmp}) {
		    print $r->[0] . "\n";
		    push(@search_results_word, $r);
		}
	    } elsif ($type eq 'WORD') {
		## 通常検索
		foreach my $r (@search_result_word) {
		    print $r->[0] . "\n";
		    push(@search_results_word, $r);
		}
	    }
	    
	    if ($type eq 'DPND') {
		foreach my $r (@search_result_dpnd) {
		    next unless (defined($r->[0]));
		    print "dpnd=$r->[0]\n";
		    push(@search_results_dpnd, $r);
		}
	    }
	}
    }
    print STDERR "$host> DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG\n";
    print STDERR "################# " . scalar(@search_results_word) . " <<<\n";
    print STDERR "################# " . scalar(@search_results_dpnd) . " <<<\n";

    if(defined($queries->[0]->{DPND})){
 	# ``全ての係り受け関係を含む''が指定されていたら
 	if ($dpnd_condition > 0) {
	    foreach my $r (@search_results_dpnd) {
		push(@search_results_word, $r);
	    }
 	}
    }
    
    my $search_result_p = \@search_results_word;
    # 検索結果の論理演算
    if($logical_cond eq 'AND'){
	print STDERR "################# " . scalar(@{$search_results_word[0]}) . " ###\n";
	$search_result_p =  &intersect_wo_hash(\@search_results_word, 0);
    }else{
	# 何もしなければ OR
    }

    # 該当文書のスコアを計算
    my $d_scores = &calculateDocumentScores($qid2gdf, $search_result_p, \@search_results_dpnd, $only_hitcount);

    return $d_scores;
}

sub returnSearchResults{
    my($new_socket, $d_scores, $required_results) = @_;

    unless($d_scores){
	print STDERR "$host> no file was found\n";
	print $new_socket "0\n";
	print $new_socket "No file was found\n";
    }else{
	my $output;
	my $count = 0;
	foreach my $did (sort{$d_scores->{$b} <=> $d_scores->{$a}} keys %{$d_scores}){
	    my $id = $did;
#	    next if($id < 0);

	    my $score = $d_scores->{$did};
	    $output .= "$id,$score\[RET\]";
	    $count++;
	    last if($count > $required_results);
	}

	my $hitcount = scalar(keys %{$d_scores});
	print STDERR "$host> local hitcount=$hitcount\n";
	print $new_socket "$hitcount\n";
	print $new_socket "$output\n";
    }
}

sub calculateDocumentScores{
    my($qid2gdf, $results_word, $results_dpnd, $only_hitcount) = @_;

    my %d_scores = ();
    my %dlength = ();
    for (my $i = 0; $i < scalar(@{$results_word}); $i++) {
	my %already = ();
	foreach my $doc (@{$results_word->[$i]}) {
	    my $did = $doc->{did};
	    if ($only_hitcount > 0) {
		$d_scores{$did}++;
	    } else {
		next if (exists($already{$did}));
		$already{$did} = 0;

		my $freq  = $doc->{freq};
		my $gdf = $qid2gdf->{$doc->{qid}};
		my $length = 1;
   		foreach my $dlength (@DOC_LENGTH_DBs) {
   		    if (exists($dlength->{$did})) {
   			$length = $dlength->{$did};
   			last;
   		    }
   		}
		$dlength{$did} = $length;
		
		my $score = &calculateOKAPIScore($freq, $gdf, $length);

		$d_scores{$did} = 0.0 unless(exists($d_scores{$did}));
		$d_scores{$did} += $score;
	    }
	}
    }

    return \%d_scores if ($only_hitcount > 0);

    # 係り受けをスコアに考慮
    for(my $i = 0; $i < scalar(@{$results_dpnd}); $i++){
  	foreach my $doc (@{$results_dpnd->[$i]}){
  	    my $did = $doc->{did};
  	    if(exists($d_scores{$did})){
  		my $freq  = $doc->{freq};
  		my $gdf = $qid2gdf->{$doc->{qid}};
  		my $length = $dlength{$did};
		
  		my $score = &calculateOKAPIScore($freq, $gdf, $length);
  		$d_scores{$did} += $score;
  	    }
  	}
    }
    
    return \%d_scores;
}

sub calculateOKAPIScore{
    my($freq, $gdf, $length) = @_;
    my $tf = (3 * $freq) / ((0.5 + 1.5 * $length / $AVE_DOC_LENGTH) + $freq);
    my $idf =  log(($N - $gdf + 0.5) / ($gdf + 0.5));

    return $tf * $idf;
}

sub intersect_wo_hash{
    my ($did_info, $near_range) = @_;
    my @results = ();
    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
	my @tmp = ();
	$results[$i] = \@tmp;
    }

    # 空リストのチェック
    foreach my $a (@{$did_info}){
	unless(defined($a)){
	    return \@results;
	}

	if(scalar(@{$a}) < 1){
	    return \@results;
	}
    }

    my $debug = 0;
    if ($debug) {
# 	for(my $i = 0; $i < scalar(@{$did_info}); $i++){
# 	    print STDERR "$i :: size: " . scalar(@{$did_info->[$i]}) . " qid=" . $did_info->[$i]->[0]->{qid} . "\n";
# 	}
    }

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)
    my @temp = sort {scalar(@{$a}) <=> scalar(@{$b})} @{$did_info};

#     if ($debug) {
# 	my $size;
# 	for (my $i = 0; $i < scalar(@temp); $i++) {
# 	    if ($i == 0) {
# 		$size = scalar(@{$temp[$i]});
# 		last;
# 	    }
# 	    print STDERR "$i :: size: " . scalar(@{$temp[$i]}) . "\n";
# 	}
#}

    # 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
    for (my $i = 0; $i < scalar(@{$temp[0]}); $i++) {
	# 対象の文書を含まない配列があった場合
	# $flagが1のままループを終了する
	my $flag = 0;
	# 一番短かい配列以外を順に調べる
	for (my $j = 1; $j < scalar(@temp); $j++) {
	    $flag = 1; 
	    while(defined($temp[$j]->[0])){
		if($temp[$j]->[0]->{did} < $temp[0]->[$i]->{did}){
		    shift(@{$temp[$j]});
		}elsif($temp[$j]->[0]->{did} == $temp[0]->[$i]->{did}){
		    $flag = 0;
		    last;
		}elsif($temp[$j]->[0]->{did} > $temp[0]->[$i]->{did}){
		    last;
		}
	    }
	    last if($flag > 0);
	}
	
	if($flag < 1){
	    push(@{$results[0]}, $temp[0]->[$i]);
	    for(my $j = 1; $j < scalar(@temp); $j++){
		push(@{$results[$j]}, $temp[$j]->[0]);
	    }
	}
    } # end of for (my $i = 0; $i < @{$did_info->[0]}; $i++)

    return \@results if($near_range < 1);

    my @new_results = ();
    for(my $i = 0; $i < scalar(@results); $i++){
	$new_results[$i] = [];
    }

    # クエリの順序でソート
    @results = sort{$a->[0]->{qid} <=> $b->[0]->{qid}} @results;

    for (my $d = 0; $d < scalar(@{$results[0]}); $d++) {
	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@results); $q++) {
	    foreach my $p (@{$results[$q]->[$d]->{pos}}) {
		push(@{$poslist[$q]}, $p);
	    }
# 	    if ($opt{debug}) {
# 		print "qid=$q :: ";
# 		foreach my $p (@{$poslist[$q]}) {
# 		    print $p . ", ";
# 		}
# 		print "\n";
# 	    }
	}

	while (scalar(@{$poslist[0]}) > 0) {
	    my $flag = 0;
	    my $pos = shift(@{$poslist[0]}); # クエリ中の先頭の単語の出現位置
	    for (my $q = 1; $q < scalar(@poslist); $q++) {
		while (1) {
		    # クエリ中の単語の出現位置リストが空なら終了
		    if (scalar(@{$poslist[$q]}) < 1) {
			$flag = 1;
			last;
		    }

# 		    if ($opt{debug}) {
# 			print "qid=$q :: $poslist[$q]->[0] ($pos)\n";
# 		    }

		    if ($pos < $poslist[$q]->[0] && $poslist[$q]->[0] < $pos + $near_range + 1) {
			$flag = 0;
			last;
		    } elsif ($poslist[$q]->[0] < $pos) {
			shift(@{$poslist[$q]});
		    } else {
			$flag = 1;
			last;
		    }
		}

		last if ($flag > 0);
		$pos = $poslist[$q]->[0];
	    }

	    if ($flag == 0) {
		for (my $q = 0; $q < scalar(@results); $q++) {
		    push(@{$new_results[$q]}, $results[$q]->[$d]);
		}
	    }
	}
    }

    return \@new_results;
}
