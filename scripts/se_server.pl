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
use Devel::Size qw(total_size);

# host名を得る
my $host = `hostname`; chop($host);

binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");

my $INDEX_DIR = shift(@ARGV);
my $PORT = shift(@ARGV);

my $DF_WORD_FP = shift(@ARGV);
my $DF_DPND_FP = shift(@ARGV);
my $DF_WNDW_FP = shift(@ARGV);

my $TOOL_HOME = '/home/skeiji/local/bin';

##############################################################
# 単語、係り受けそれぞれについて文書頻度データベースをロード #
##############################################################
print STDERR "$host> loading df database...\n";

tie my %df_word_cdb, 'CDB_File', $DF_WORD_FP or die "$0: can't tie to $DF_WORD_FP $!\n";
tie my %df_dpnd_cdb, 'CDB_File', $DF_DPND_FP or die "$0: can't tie to $DF_DPND_FP $!\n";
# tie my %df_wndw_cdb, 'CDB_File', $DF_WNDW_FP or die "$0: can't tie to $DF_WNDW_FP $!\n";

my $DF_WORD_DB = \%df_word_cdb;
my $DF_DPND_DB = \%df_dpnd_cdb;
# my $DF_WNDW_DB = \%df_wndw_cdb;

my $ret_word = new Retrieve($INDEX_DIR, 'word');
my $ret_dpnd = new Retrieve($INDEX_DIR, 'dpnd');
my $ret_3grm = new Retrieve($INDEX_DIR, '3grm');

# my $ret_title_word = new Retrieve($INDEX_DIR, 'title.word');
# my $ret_title_dpnd = new Retrieve($INDEX_DIR, 'title.dpnd');

print STDERR "$host> done.\n";
print STDERR "$host> port=$PORT\n";
print STDERR "$host> index_dir=$INDEX_DIR\n";
print STDERR "$host> ready!\n";

######################################################################
# 全文書数
#our $N = 48420000;
my $N = 51000000;
# 平均文書長
my $AVE_DOC_LENGTH = 871.925373263118;
# デバッグモード
my $DEBUG = 1;
######################################################################

&main();

###########################################################
# 単語、係り受けそれぞれの文書頻度データベースをuntieする #
###########################################################
untie %df_word_cdb;
untie %df_dpnd_cdb;
# untie %df_wndw_cdb;

sub makeDF_TRI_DB{
    my($queries) = @_;
    my %DF_TRI_DB = ();

    opendir(DIR, "/home/skeiji/trigram_df2");
    foreach my $cdbf (readdir(DIR)){
	next unless($cdbf =~ /cdb$/);

	my $cdbfp = "/home/skeiji/trigram_df2/$cdbf";
	tie my %df_cdb, 'CDB_File', $cdbfp or die "$0: can't tie to $cdbfp $!\n";
	foreach my $q (@{$queries}){
	    my $kwd = $q->{keyword};
	    if(exists($df_cdb{$kwd})){
		$DF_TRI_DB{$kwd} = 0 unless(exists($DF_TRI_DB{$kwd}));
		$DF_TRI_DB{$kwd} += $df_cdb{$kwd};
	    }
	}
	untie %df_cdb;
    }
    closedir(DIR);

    return \%DF_TRI_DB;
}

sub main{
    my $listening_socket = IO::Socket::INET->new(LocalPort => $PORT,
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
		print STDERR "$host> sleep $sleeptime seconds. [API ACCESS]\n";
		sleep($sleeptime);
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
	    exit;
	}
    }
}

sub get{
    my($fid,$new_socket) = @_;
    $fid =~ /(....)\d+/;
    my $dir = 'x' . $1 . '_idx';
#   my $filepath = "$INDEX_DIR/$dir/$fid.idx";
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
    my($input) = @_;
    my($input_3grm, $input_lang) = split(/ /, $input);

    my $qid = 0;
    my %queries = ();
    my %qid2gdf = ();
    foreach my $k (split(':',$input_3grm)){
	next if($k eq 'null');

	push(@{$queries{TRIGRAM}}, {keyword => $k, id => $qid++, gdf => 0});
    }

    if(defined($queries{TRIGRAM})){
	my $DF_TRI_DB = &makeDF_TRI_DB($queries{TRIGRAM});
	foreach my $q (@{$queries{TRIGRAM}}){
	    $q->{gdf} = $DF_TRI_DB->{$q->{keyword}};
	}
    }

    foreach my $k (split(/:/, $input_lang)){
	next if(index($k, "->") > 0);
	next if(index($k, "##") > 0);

	my $gdf = $DF_WORD_DB->{$k};
	$qid2gdf{$qid} = $gdf;
	push(@{$queries{WORD}}, {keyword => $k, id => $qid++, gdf => $gdf});
    }

    foreach my $k (split(/:/, $input_lang)){
	next unless(index($k, "->") > 0);

	my $gdf = $DF_DPND_DB->{$k};
	$qid2gdf{$qid} = $gdf;
	push(@{$queries{DPND}}, {keyword => $k, id => $qid++, gdf => $gdf});
    }

#      foreach my $k (split(/:/, $input_lang)){
#  	next unless(index($k, "##") > 0);

#  	my $gdf = $DF_WNDW_DB->{$k};
#  	$qid2gdf{$qid} = 1; #$gdf;
#  	push(@{$queries{WNDW}}, {keyword => $k, id => $qid++, gdf => $gdf});
#      }

    return (\%queries, \%qid2gdf);
}
    
sub search_wo_hash{
    my($input,$ranking_method,$logical_cond,$sf_level,$dep_cond,$required_results,$new_socket) = @_;

    # サーバーから送信されてきたユーザのクエリをトライグラムと単語・係り受けに分類

    my($queries, $qid2gdf) = &parseInput($input);


    if($DEBUG){
	print STDERR "$host> DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG\n";
	foreach my $type (keys %{$queries}){
	    my @q_list = @{$queries->{$type}};
	    for(my $i = 0; $i < scalar(@q_list); $i++){
		my $kwd = $q_list[$i]->{keyword};
		my $qid = $q_list[$i]->{id};
		my $gdf = $q_list[$i]->{gdf};
		print STDERR "$host> $type :: $i qid=$qid keyword=$kwd gdf=$gdf\n";
	    }
	}
	print STDERR "$host> DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG\n";
    }

    # 単語と係り受けに関する検索
    my $result_word = $ret_word->search_wo_hash($queries->{WORD});
    my $result_dpnd = $ret_dpnd->search_wo_hash($queries->{DPND});
#    my $result_title_word = $ret_title_word->search_wo_hash($queries->{WORD});
#    my $result_title_dpnd = $ret_title_dpnd->search_wo_hash($queries->{DPND});

    # トライグラムに関する検索の開始
    my $result_3grm;
    if(defined($queries->{TRIGRAM})){
	$result_3grm = $ret_3grm->search_wo_hash($queries->{TRIGRAM});
 	$result_3grm = &intersect_wo_hash($result_3grm);
    }
    
    
    # トライグラムと単語検索結果のマージ
    my $results;
    unless(defined($queries->{WORD})){
	$results = $result_3grm;
    }else{
	$results = $result_word;
	foreach my $r (@{$result_3grm}){
	    push(@{$results}, $r);
	}
    }
    
    # 検索結果の論理演算
    if($logical_cond eq 'AND'){
	$results =  &intersect_wo_hash($results);
    }else{
	# 何もしなければ OR
    }

#    my $mem_size = (1.0 * total_size($results) / (1000 * 1000));
#    printf STDERR ("%s> mem_size=%.3f [MB]\n", $host, $mem_size);

    # 該当文書のスコアを計算
#   my $d_scores = &calculateDocumentScores($results, $result_dpnd, $result_title_word, $result_title_dpnd, $qid2gdf);
    my $d_scores = &calculateDocumentScores($qid2gdf, $results, $result_dpnd);

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
    my($qid2gdf, $results_word, $results_dpnd, $results_title_word, $results_title_dpnd) = @_;
    my %d_scores = ();

    for(my $i = 0; $i < scalar(@{$results_word}); $i++){
	foreach my $doc (@{$results_word->[$i]}){
	    my $did = $doc->{did};
	    my $freq  = $doc->{freq};
	    my $gdf = $qid2gdf->{$doc->{qid}};
	    my $length = $doc->{length};

	    my $score = &calculateOKAPIScore($freq, $gdf, $length);
	    $d_scores{$did} = 0.0 unless(exists($d_scores{$did}));
	    $d_scores{$did} += $score;
	}
    }

    # 係り受けをスコアに考慮
    for(my $i = 0; $i < scalar(@{$results_dpnd}); $i++){
 	foreach my $doc (@{$results_dpnd->[$i]}){
 	    my $did = $doc->{did};
 	    if(exists($d_scores{$did})){
 		my $freq  = $doc->{freq};
 		my $gdf = $qid2gdf->{$doc->{qid}};
 		my $length = $doc->{length};
		
 		my $score = &calculateOKAPIScore($freq, $gdf, $length);
 		$d_scores{$did} += $score;
 	    }
 	}
    }

    # titleをスコアに考慮
#     for(my $i = 0; $i < scalar(@{$results_title_word}); $i++){
#  	foreach my $doc (@{$results_title_word->[$i]}){
#  	    my $did = $doc->{did};
#  	    if(exists($d_scores{$did})){
#  		my $freq  = $doc->{freq};
#  		my $gdf = $qid2gdf->{$doc->{qid}};
#  		my $length = $doc->{length};
		
#  		my $score = &calculateOKAPIScore($freq, $gdf, $length);
#  		$d_scores{$did} += $score;
#  	    }
#  	}
#     }

#     # 近接をスコアに考慮
#     for(my $i = 0; $i < scalar(@{$results_wndw}); $i++){
#  	foreach my $doc (@{$results_wndw->[$i]}){
#  	    my $did = $doc->{did};
#  	    if(exists($d_scores{$did})){
#  		my $freq  = $doc->{freq};
#  		my $gdf = 1;#$qid2gdf->{$doc->{qid}};
#  		my $length = $doc->{length};
		
#  		my $score = &calculateOKAPIScore($freq, $gdf, $length);
#  		$d_scores{$did} += $score;
#  	    }
#  	}
#     }
    
    return \%d_scores;
}

sub calculateOKAPIScore{
    my($freq, $gdf, $length) = @_;
    my $tf = (3 * $freq) / ((0.5 + 1.5 * $length / $AVE_DOC_LENGTH) + $freq);
    my $idf =  log(($N - $gdf + 0.5) / ($gdf + 0.5));

    return $tf * $idf;
}

sub intersect_with_hash{
    my ($doc_info, $q_num) = @_;

    foreach my $did (keys %{$doc_info}){
	my $size = scalar(keys %{${$doc_info->{$did}}->{qid2tf}});
	if($size < $q_num){
	    delete($doc_info->{$did});
	}
    }
	    
    return $doc_info;
}


sub intersect_wo_hash{
    my ($did_info) = @_;
    my @results = ();
    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
	my @tmp = ();
	$results[$i] = \@tmp;
    }

    # 空リストのチェック
    foreach my $a (@{$did_info}){
	unless(defined($a)){
# 	    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
# 		my @tmp = ();
# 		$results[$i] = \@tmp;
# 	    }
	    return \@results;
	}

	if(scalar(@{$a}) < 1){
# 	    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
# 		my @tmp = ();
# 		$results[$i] = \@tmp;
# 	    }
	    return \@results;
	}
    }

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)

#    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
#	print STDERR "$i :: size: " . scalar(@{$did_info->[$i]}) . "\n";
#    }

    my @temp = sort {scalar(@{$a}) <=> scalar(@{$b})} @{$did_info};

#    my $size;
#    for(my $i = 0; $i < scalar(@temp); $i++){
#	if($i == 0){
#	    $size = scalar(@{$temp[$i]});
#	    last;
#	}
#	print STDERR "$i :: size: " . scalar(@{$temp[$i]}) . "\n";
#    }

#    print STDERR ">>>>>>>>>>>>>>>>>>>>\n";

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

    return \@results;
}

sub compressDocuments_with_hash{
    my ($doc_info) = @_;
    my %rbuff = ();
    my $id = 0;
    my %query2id = ();
#     foreach my $did (keys %{$doc_info}){
# 	my $result;
# 	if(exists($rbuff{$did})){
# 	    $result = $rbuff{$did};
# 	}else{
# 	    $result = {did => $did, length => $doc->{length}, tfs => undef, gdfs => undef};
# 	}

# 	my $qid;
# 	    if(exists($query2id{$doc->{query}})){
# 		$qid = $query2id{$doc->{query}};
# 	    }else{
# 		$qid = $id;
# 		$query2id{$doc->{query}} = $id;
# 		$id++;
# 	    }

# 	    $result->{tfs}->{$qid}  = $doc->{freq};
# 	    $result->{gdfs}->{$qid} = $doc->{gdf};

# 	    $rbuff{$did} = $result;
# 	}
#     }

    my @results = ();
    foreach my $did (keys %rbuff){
	push(@results, $rbuff{$did});
    }
    return \@results;
}

sub compressDocuments_wo_hash{
    my ($doc_info) = @_;
    my %rbuff = ();
    my $id = 0;
    my %query2id = ();
    for (my $i = 0; $i < scalar(@{$doc_info}); $i++) {
	foreach my $doc (@{$doc_info->[$i]}){
	    my $did = $doc->{did};
	    my $result;
	    if(exists($rbuff{$did})){
		$result = $rbuff{$did};
	    }else{
		$result = {did => $did, length => $doc->{length}, tfs => undef, gdfs => undef};
	    }

	    my $qid;
	    if(exists($query2id{$doc->{query}})){
		$qid = $query2id{$doc->{query}};
	    }else{
		$qid = $id;
		$query2id{$doc->{query}} = $id;
		$id++;
	    }

	    $result->{tfs}->{$qid}  = $doc->{freq};
	    $result->{gdfs}->{$qid} = $doc->{gdf};

	    $rbuff{$did} = $result;
	}
    }

    my @results = ();
    foreach my $did (keys %rbuff){
	push(@results, $rbuff{$did});
    }
    return \@results;
}
