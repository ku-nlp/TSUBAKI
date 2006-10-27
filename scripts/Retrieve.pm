package Retrieve;

# $Id$

###################################################################
# 与えられた単語を含む文書IDをindex<NAME>.datから検索するモジュール
###################################################################

use strict;
use BerkeleyDB;
use Encode;
use utf8;
use FileHandle;

######################################################################
# 全文書数
our $N = 23000000;
######################################################################


sub new {
    my ($class, $dir) = @_;

    my $this = {IN => [], OFFSET => [], FILE_NUM => 0};

    # idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
    opendir(DIR, $dir) or die "$dir: $!\n";

    for my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next if $d !~ /idx(.+).dat/;
	my $NAME = $1;

	# ファイル(idx*.dat)をオープンする
	$this->{IN}[$this->{FILE_NUM}] = new FileHandle;
	open($this->{IN}[$this->{FILE_NUM}], "< $dir/idx$NAME.dat") or die "$dir/idx$NAME.dat: $!\n";

	# OFFSET(offset*.dat)を読み込み専用でtie
	my $table =  tie %{$this->{OFFSET}[$this->{FILE_NUM}]}, 'BerkeleyDB::Hash', -Filename => "$dir/offset$NAME.db", -Flags => DB_RDONLY or die "$!\n";
	&_encode_db($table);
	$this->{FILE_NUM}++;
    }

    closedir(DIR);

    bless $this;
}

sub search {
    my($this, $key, $ranking_method, $logical_cond,$DF) = @_;

    my @query_list = split(/[\s　]+/, $key);
    my @df;
#   my %did_info;
    my @did_info;

    # idxごとに処理
    for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {

	for (my $k = 0; $k < @query_list; $k++) {
	    my $query = $query_list[$k];
	    next unless defined $this->{OFFSET}[$f_num]{$query};
	    seek($this->{IN}[$f_num], $this->{OFFSET}[$f_num]{$query}, 0);

	    my $char;
	    my @str;
	    my $buf;
	    while (read($this->{IN}[$f_num], $char, 1)) {
		if (unpack('c', $char) != 0) {
		    push(@str, $char);
		}
		else {
		    # 最初はキーワード（情報としては冗長）
		    $buf = join('', @str);
		    @str = ();
		    my $word = encode('euc-jp',$query);
		    $df[$k] = $DF->{$word};
		    print STDERR ">> word=$word, df=" . $DF->{$word} . "\n";

		    # 次にキーワードの文書頻度
		    read($this->{IN}[$f_num], $buf, 4);
		    my $size = unpack('L', $buf);
#		    $df[$k] = $size;

		    # 文書IDと出現頻度
		    for (my $i = 0; $i < $size; $i++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $did = unpack('L', $buf);
			read($this->{IN}[$f_num], $buf, 4);
			my $freq = unpack('L', $buf);

#			$did_info{$did}{freq}[$k] = $freq; 
			push(@{$did_info[$k]}, {qid => $k, did => $did, freq => $freq});
		    }
		    last;
		}
	    }
	}
    }

    for(my $j = 0; $j < scalar(@did_info); $j++){
	next unless(defined($did_info[$j]));
	print STDERR "$j: " . scalar(@{$did_info[$j]}) . "\n";
    }
    print STDERR "($logical_cond)\n";
    if($logical_cond eq "AND" && scalar(@did_info) > 1){
	my $arryref = &intersect_wo_hash(\@did_info,scalar(@query_list));
	return () unless(defined($arryref));
	@did_info = @{$arryref};
    }

    for(my $j = 0; $j < scalar(@did_info); $j++){
	print STDERR "$j: " . scalar(@{$did_info[$j]}) . "\n";
    }

    if(scalar(@did_info) < 1){
	print STDERR "ERROR.\n";
	return ();
    }else{
	if($ranking_method eq "TFIDF"){
#	    return &_calc_d_score_TF_IDF(\%did_info, scalar(@query_list), \@df);
	    return &_calc_d_score_TF_IDF_wo_hash(\@did_info, scalar(@query_list), \@df);
	}elsif($ranking_method eq "OKAPI"){
#	    return &_calc_d_score_OKAPI(\%did_info, scalar(@query_list), \@df);
	    return &_calc_d_score_OKAPI_wo_hash(\@did_info, scalar(@query_list), \@df);
	}else{
	    # FREQ
#	    return &_calc_d_score_AND(\%did_info, scalar(@query_list));
	    return &_calc_d_score_FREQ_wo_hash(\@did_info, scalar(@query_list));
	}
    }
}   

sub DESTROY {
    my ($this) = @_;

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {
	$this->{IN}[$f_num]->close;
	untie %{$this->{OFFSET}[$this->{FILE_NUM}]};
    }
}

######################################################################
# AND(ハッシュを使わない高速版)

sub _calc_d_score_AND_wo_hash {
    my ($did_info, $key_num) = @_;
    my (@result) = ();

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)
    @{$did_info} = sort {scalar(@{$a}) <=> scalar(@{$b})} @{$did_info};

    # 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
    for (my $i = 0; $i < @{$did_info->[0]}; $i++) {

	# 対象の文書を含まない配列があった場合
	# $flagが1のままループを終了する
	my $flag;

	# 一番短かい配列以外を順に調べる
	for (my $k = 1;  $k < $key_num; $k++) {
	    $flag = 1; 

	    while (@{$did_info->[$k]}) {
		if ($did_info->[$k][0] < $did_info->[0][$i]) {
		    shift(@{$did_info->[$k]});
		}
		elsif ($did_info->[$k][0] == $did_info->[0][$i]) {
		    $flag = 0;
		    last;
		}
		elsif ($did_info->[$k][0] > $did_info->[0][$i]) {
		    last;
		}
	    }
	    last if ($flag);
	}
	push(@result, {"did" => $did_info->[0][$i], "score" => 1}) if (!$flag);
    }
    return @result;
}

sub _calc_d_score_FREQ_wo_hash{
    my ($did_info, $key_num, $df) = @_;
    my (@result) = ();

    my %did2index = {};
    foreach my $k (@{$did_info}){
	for(my $i = 0; $i < scalar(@{$did_info->[$k]}); $i++){
	    my $did = $did_info->[$k]->{did};
	    my $freq = $did_info->[$k]->{freq};

	    my $index = scalar(@result);
	    if(exists($did2index{$did})){
		$index = $did2index{$did};
		$result[$index]->{score} += $freq;
	    }else{
		$did2index{$did} = $index;
		push(@result, {did => $did, score => $freq});
	    }
	}
    }
    return sort {$b->{score} <=> $a->{score}} @result;
}


######################################################################
# intersect

sub intersect{
    my ($did_info, $key_num) = @_;
    my (%result) = {};

    foreach my $did (keys(%{$did_info})){
	my $flag = 1;
	for(my $k = 0; $k < $key_num; $k++){
	    if(!defined $did_info->{$did}{freq}[$k]){
		if(exists($result{$did})){
		    delete($result{$did});
		}
		last;
	    }else{
		unless(exists($result{$did})){
		    $result{$did} = {freq => []};
		}
		$result{$did}{freq}[$k] = $did_info->{$did}{freq}[$k];
	    }
	}
    }
    return %result;
}

sub intersect_wo_hash{
    my ($did_info, $key_num) = @_;
    my (@result) = ();

    ## 空の配列があるかどうかのチェック
    my @atemp = ();
    for(my $i = 0; $i < scalar(@{$did_info}); $i++){
	return () unless(defined($did_info->[$i]));

	if(scalar(@{$did_info->[$i]}) > 0){
	    my @tmp = sort{$a->{did} <=> $b->{did}} @{$did_info->[$i]};
	    push(@atemp, \@tmp);
#	    foreach my $d (@tmp){
#		print STDERR ">> $d->{did}\n";
#	    }
	}else{
	    return ();
	}
#	print STDERR "-----\n";
    }

#    my @tmp;
#    for(my $i = 0; $i < scalar(@atemp); $i++){
#	my $size = scalar(@{$atemp[$i]});
#	print STDERR "$atemp[$i] $size\n";
#	for(my $j = 0; $j < $size; $j++){
#	    push(@tmp, sort{$atemp[$i]->[$a]->{did} <=> $atemp[$i]->[$b]->{did}} $atemp[$i]);
#	}
#    }
#    print STDERR "-----\n";
    

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)
    my @temp = sort {scalar(@{$a}) <=> scalar(@{$b})} @atemp;
#    for(my $i = 0; $i < scalar(@{$temp[0]}); $i++){
#	print ">>> $temp[0]->[$i]->{did}\n";
#    }
    $did_info = \@temp;
    # 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
    print STDERR ">>>" . scalar(@{$did_info}) . "<<<\n";
    for (my $i = 0; $i < scalar(@{$did_info->[0]}); $i++) {

	# 対象の文書を含まない配列があった場合
	# $flagが1のままループを終了する
	my $flag = 0;
	# 一番短かい配列以外を順に調べる
	for (my $k = 1;  $k < $key_num; $k++) {
	    $flag = 1; 
	    while(defined($did_info->[$k]->[0])){
		if($did_info->[$k]->[0]->{did} < $did_info->[0]->[$i]->{did}){
		    shift(@{$did_info->[$k]});
		}elsif($did_info->[$k]->[0]->{did} == $did_info->[0]->[$i]->{did}){
		    $flag = 0;
		    last;
		}elsif($did_info->[$k]->[0]->{did} > $did_info->[0]->[$i]->{did}){
		    last;
		}
	    }
	    last if($flag > 0);
	}
	
	if($flag < 1){
	    push(@{$result[0]}, $did_info->[0]->[$i]);
	    for(my $k = 1; $k < $key_num; $k++){
		push(@{$result[$k]}, $did_info->[$k]->[0]);
	    }
	}
    } # end of for (my $i = 0; $i < @{$did_info->[0]}; $i++)
    return \@result;
}

sub _calc_d_score_AND {

    my ($did_info, $key_num) = @_;
    my (@result) = ();

    foreach my $did (keys(%{$did_info})) {
	my $flag = 1;
	for (my $k = 0; $k < $key_num; $k++) {
	    if (!defined $did_info->{$did}{freq}[$k]) {
		$flag = 0;
		last;
	    }
	    else {
		$did_info->{$did}{FREQ} += $did_info->{$did}{freq}[$k];
	    }
	}
	if ($flag) {
	    push(@result, {"did" => $did, "score" => $did_info->{$did}{FREQ}});
	}
    }
    return sort {$b->{score} <=> $a->{score}} @result;
}

######################################################################
# TFIDF

sub _calc_d_score_TF_IDF {
    my ($did_info, $key_num, $df) = @_;
    my (@result) = ();

    foreach my $did (keys(%{$did_info})) {
	my $flag = 1;
	for (my $k = 0; $k < $key_num; $k++) {
	    if (defined $did_info->{$did}{freq}[$k]) {
		$did_info->{$did}{FREQ} += $did_info->{$did}{freq}[$k];
		$did_info->{$did}{score} += $did_info->{$did}{freq}[$k] * log($N/$df->[$k]);
	    }
	}
	push(@result, {"did" => $did, "score" => $did_info->{$did}{score}});
    }
    return sort {$b->{score} <=> $a->{score}} @result;
}

sub _calc_d_score_TF_IDF_wo_hash{
    my ($did_info, $key_num, $df) = @_;
    my (@result) = ();

    my %did2index = {};
    foreach my $k (@{$did_info}) {
	for(my $i = 0; $i < scalar(@{$k}); $i++){
	    my $did = $k->[$i]->{did};
	    my $freq = $k->[$i]->{freq};
	    my $qid = $k->[$i]->{qid};
	    my $score = $freq * log($N/$df->[$qid]);

	    my $index = scalar(@result);
	    if(exists($did2index{$did})){
		$index = $did2index{$did};
		$result[$index]->{score} += $score;
	    }else{
		$did2index{$did} = $index;
		push(@result, {did => $did, score => $score});
	    }
	}
    }
    return sort {$b->{score} <=> $a->{score}} @result;
}

######################################################################
# OKAPI

sub _calc_d_score_OKAPI {

    my ($did_info, $key_num, $df) = @_;
    my (@result) = ();

    foreach my $did (keys(%{$did_info})) {
	my $flag = 1;
	for (my $k = 0; $k < $key_num; $k++) {
	    if (defined $did_info->{$did}{freq}[$k]) {
		$did_info->{$did}{FREQ} += $did_info->{$did}{freq}[$k];
		$did_info->{$did}{score} += (3 * $did_info->{$did}{freq}[$k] / (2 + $did_info->{$did}{freq}[$k])) * log(($N - $df->[$k] + 0.5) / ($df->[$k] + 0.5));
	    }
	}
	push(@result, {"did" => $did, "score" => $did_info->{$did}{score}});
    }
    return sort {$b->{score} <=> $a->{score}} @result;
#    return @result;
}

sub _calc_d_score_OKAPI_wo_hash{
    my ($did_info, $key_num, $df) = @_;
    my (@result) = ();

    my %did2index = ();
    foreach my $k (@{$did_info}) {
	for(my $i = 0; $i < scalar(@{$k}); $i++){
	    my $did = $k->[$i]->{did};
	    my $freq = $k->[$i]->{freq};
	    my $qid = $k->[$i]->{qid};
	    my $score = ((3 * $freq) / (2 + $freq)) * log(($N - $df->[$qid] + 0.5) / ($df->[$qid] + 0.5));

	    my $index = scalar(@result);
	    if(exists($did2index{$did})){
		$index = $did2index{$did};
		$result[$index]->{score} += $score;
	    }else{
		$did2index{$did} = $index;
		push(@result, {did => $did, score => $score});
	    }
	}
    }
    return sort {$b->{score} <=> $a->{score}} @result;
}


######################################################################		
# データベースのエンコード設定
sub _encode_db {
    my ($db) = @_;
    $db->filter_fetch_key(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_key(sub {$_ = &encode('euc-jp', $_)});
    $db->filter_fetch_value(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_value(sub {$_ = &encode('euc-jp', $_)});
}

1;
