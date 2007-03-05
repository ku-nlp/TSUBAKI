package Indexer;

###################################################################
# juman, knpの解析結果から索引付けする要素を抽出するモジュール
###################################################################

use strict;
use utf8;

our @EXPORT = qw(makeIndexfromJumanResult makeIndexfromKnpResult makeNgramIndex makeIndexfromIndexArray);

sub new {
    my($class);
    my $this = {absolute_pos => -1};

    bless $this;
}

sub DESTROY {}

## JUMANの解析結果から索引語を抽出する
sub makeIndexfromJumanResult{
    my($this,$juman_result) = @_;
    my %index = ();
    my @buff = ();
    my $size = 0;
    foreach my $line (split(/\n/,$juman_result)){
	next if ($line =~ /^(\<|EOS)/);

	## 代表表記が曖昧だったら
	if($line =~ /^@ /){
	    push(@{$buff[$size-1]}, "$'");
	}else{
	    push(@{$buff[$size++]}, $line);
	}
    }

    my $pos = 0;
    foreach my $e (@buff){
	my @daihyou = @{$e};
	my $num_daihyou = scalar(@daihyou);
	foreach my $line (@daihyou){
	    my @w = split(/\s+/, $line);
	    next if (&containsSymbols($w[2]) > 0); # 記号を削除

	    # 削除する条件
	    next if ($w[2] =~ /^[\s*　]*$/);
	    next if ($w[3] eq "助詞");
	    next if ($w[5] =~ /^(句|読)点$/);
	    next if ($w[5] =~ /^空白$/);
	    next if ($w[5] =~ /^(形式|副詞的)名詞$/);

	    my $word = $w[2];
	    if($line =~ /代表表記:(.+?)\//){
		$word = $1;
	    }
	    $word = "Ｗ杯" if($word eq "ワールドカップ");

	    $word = &toUpperCase_utf8($word);
	    $index{$word}->{score} = 0 unless(exists($index{$word}));
	    $index{$word}->{score} += (1 / $num_daihyou);
	    $index{$word}->{pos} = $pos;
	}
	$pos++;
	$this->{absolute_pos}++;
    }
    
    return \%index;
}

sub makeIndexArrayfromJumanResult{
    my($this,$juman_result) = @_;
    my @buff = ();
    my $size = 0;
    foreach my $line (split(/\n/,$juman_result)){
	next if ($line =~ /^(\<|EOS)/);

	## 代表表記が曖昧だったら
	if($line =~ /^@ /){
	    push(@{$buff[$size-1]}, "$'");
	}else{
	    push(@{$buff[$size++]}, $line);
	}
    }

    my $pos = 0;
    my @index_array;
    foreach my $e (@buff){
	my @daihyou = @{$e};
	my $num_daihyou = scalar(@daihyou);
	my @buff = ();
	foreach my $line (@daihyou){
	    my @w = split(/\s+/, $line);
	    next if (&containsSymbols($w[2]) > 0); # 記号を削除

	    # 削除する条件
	    next if ($w[2] =~ /^[\s*　]*$/);
	    next if ($w[3] eq "助詞");
	    next if ($w[5] =~ /^(句|読)点$/);
	    next if ($w[5] =~ /^空白$/);
	    next if ($w[5] =~ /^(形式|副詞的)名詞$/);

	    my $word = $w[2];
	    if($line =~ /代表表記:(.+?)\//){
		$word = $1;
	    }
	    $word = "Ｗ杯" if($word eq "ワールドカップ");

	    my $index_obj = {
		word => &toUpperCase_utf8($word),
		freq => (1 / $num_daihyou)
		};
	    push(@buff, $index_obj);
	}
	next if(scalar(@buff) < 1);
	push(@index_array, \@buff);
    }
    return \@index_array;
}

## KNPの解析結果から索引語と索引付け対象となる係り受け関係を抽出する
# sub makeIndexfromKnpResult{
#     my($knp_result) = @_;

#     my %freq;
#     foreach my $sent (split(/EOS\n/, $knp_result)){
# 	my $pos = -1;
# 	my $kakariSaki = -1;
# 	my @bps = ();
# 	foreach my $line (split(/\n/,$sent)){
# 	    next if($line =~ /^\* \-?\d/);

# 	    if($line =~ /^\+ (\-?\d+)(P|D|d|A)/){
# 		$pos++;
# 		$kakariSaki = $1;
# 		$bps[$pos] = {kakarisaki => $kakariSaki,
# 			      words => [],
# 			      type => $2
# 			      };
# 	    }else{
# 		next if ($line =~ /^(\<|\@|EOS)/);

# 		my @m = split(/\s+/, $line);
# 		## <意味有>タグが付与された形態素を索引付けする
# 		if($line =~ /\<意味有\>/){
# 		    next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
# 		    next if (&containsSymbols($m[2]) > 0); ## <記号>タグがついてない記号を削除

# 		    my $word = $m[2];
# 		    my @reps = ();
# 		    ## 代表表記の取得
# 		    if($line =~ /代表表記:(.+?)\//){
# 			$word = $1;
# 		    }

# 		    push(@reps, &toUpperCase_utf8($word));
# 		    ## 代表表記に曖昧性がある場合は全部保持する
# 		    while($line =~ /\<ALT(.+?)\>/){
# 			$line = "$'";
# 			if($1 =~ /代表表記:(.+?)\//){
# 			    push(@reps, &toUpperCase_utf8($1));
# 			}
# 		    }
# 		    push(@{$bps[$pos]->{words}}, \@reps);
# 		}
# 	    } # end of else
# 	} # end of foreach my $line (split(/\n/,$sent))

# 	## <意味有>が付いている形態素の代表表記を索引付け
# 	## 代表表記が複数個ある場合は代表表記の個数で割ってカウントする
# 	for(my $i = 0; $i < scalar(@bps); $i++){
# 	    next unless(defined($bps[$i]->{words}));

# 	    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
# 		my $daihyou = $bps[$i]->{words}->[$j];
# 		my $num_daihyou = scalar(@{$daihyou});
# 		for(my $k = 0; $k < $num_daihyou; $k++){
# 		    $freq{"$daihyou->[$k]"} += (1/$num_daihyou);
# 		}
# 	    }
# 	}

# 	## <意味有>が付いている形態素間の係り受け関係を索引付け
# 	## 係り先・係り元に代表表記が複数個ある場合は、係り先・元の代表表記の個数の積で割ってカウントする
# 	for(my $i = 0; $i < scalar(@bps); $i++){
# 	    my $kakariSaki = $bps[$i]->{kakarisaki};
# 	    my $kakariType = $bps[$i]->{type};
# 	    next if($kakariType eq 'P');

# 	    ## 基本句が文末なら
# 	    if($kakariSaki < 0){
# 		## <意味有>タグが付いている形態素が1つ
# 		if(scalar($bps[$i]->{words}) < 2){
# 		    next;
# 		}else{
# 		    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
# 			my $daihyou = $bps[$i]->{words}->[$j];
# 			my $num_daihyou_moto = scalar(@{$daihyou});
# 			for(my $k = 0; $k < $num_daihyou_moto; $k++){
# 			    my $kakariSakiDaihyou;
# 			    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
# 			    ## ex)
# 			    ## 河野洋平
# 			    ## 河野->洋平
# 			    if($j + 1 < scalar(@{$bps[$i]->{words}})){
# 				## 隣りの形態素に係る
# 				$kakariSakiDaihyou = $bps[$i]->{words}->[$j+1];
# 			    }else{
# 				## 末尾の基本句なので終了(係り先なし)
# 				next;
# 			    }
# 			    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

# 			    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
# 			    for(my $l = 0; $l < $num_daihyou_saki; $l++){
# 				$freq{$daihyou->[$k] . "->" . $kakariSakiDaihyou->[$l]} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
# 			    }
# 			}
# 		    }
# 		}
# 		next;
# 	    }

# 	    next unless(defined($bps[$i]->{words})); ## <意味有>タグが付いている形態素が基本句に無いなら

# 	    ## $i番目の基本句に含まれる形態素と、その係り先の基本句(曖昧性がある場合は全て)
# 	    ## との組を索引付け
# 	    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
# 		my $daihyou = $bps[$i]->{words}->[$j];
# 		my $num_daihyou_moto = scalar(@{$daihyou});

# 		for(my $k = 0; $k < $num_daihyou_moto; $k++){
# 		    my $kakariSakiDaihyou;
# 		    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
# 		    ## ex)
# 		    ## 河野洋平と/行った。
# 		    ## 河野->洋平 洋平->行く
# 		    if($j + 1 < scalar(@{$bps[$i]->{words}})){
# 			## 隣りの形態素に係る
# 			$kakariSakiDaihyou = $bps[$i]->{words}->[$j+1];
# 		    }else{
# 			## 基本句全体で係っていた基本句に係る
# 			$kakariSakiDaihyou = $bps[$kakariSaki]->{words}->[0];
# 		    }

# 		    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

# 		    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
# 		    for(my $l = 0; $l < $num_daihyou_saki; $l++){
# 			$freq{$daihyou->[$k] . "->" . $kakariSakiDaihyou->[$l]} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
# 		    }
# 		}
# 	    }
# 	}
#     }
#     return \%freq;
# }

## KNPの解析結果から索引語と索引付け対象となる係り受け関係を抽出する
sub makeIndexfromKnpResult{
    my($this,$knp_result) = @_;

    my %freq;
    foreach my $sent (split(/EOS\n/, $knp_result)){
	my $w_pos = -1;
	my $bp_pos = -1;
	my $kakariSaki = -1;
	my $kakariType = undef;
	my @bps = ();
	foreach my $line (split(/\n/,$sent)){
	    next if($line =~ /^\* \-?\d/);

 	    if($line =~ /^\+ (\-?\d+)([a-zA-Z])/){
		$bp_pos++;
		$kakariSaki = $1;
		$kakariType = $2;
		$bps[$bp_pos] = {kakarisaki => $kakariSaki,
				 kakaritype => $kakariType,
				 words => [],
				 w_poss => [],
				 ab_w_poss => []
		};
	    }else{
		next if ($line =~ /^(\<|\@|EOS)/);

		my @m = split(/\s+/, $line);
		$w_pos++;
		$this->{absolute_pos}++;
		## <意味有>タグが付与された形態素を索引付けする
		if($line =~ /\<意味有\>/){
		    next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		    next if (&containsSymbols($m[2]) > 0); ## <記号>タグがついてない記号を削除

		    my $word = $m[2];
		    my @reps = ();
		    ## 代表表記の取得
		    if($line =~ /代表表記:(.+?)\//){
			$word = $1;
		    }
		    $word = "Ｗ杯" if($word eq "ワールドカップ");

		    push(@reps, &toUpperCase_utf8($word));
		    ## 代表表記に曖昧性がある場合は全部保持する
		    while($line =~ /\<ALT(.+?)\>/){
			$line = "$'";
			if($1 =~ /代表表記:(.+?)\//){
			    push(@reps, &toUpperCase_utf8($1));
			}
		    }
		    push(@{$bps[$bp_pos]->{words}},\@reps);
		    push(@{$bps[$bp_pos]->{w_poss}}, $w_pos);
		    push(@{$bps[$bp_pos]->{ab_w_poss}}, $this->{absolute_pos});
		}
	    } # end of else
	} # end of foreach my $line (split(/\n/,$sent))

	for(my $pos = scalar(@bps); $pos > 0; $pos--){
	    print "# $bps[$pos-1]->{kakarisaki}\n";
	    if($bps[$pos-1]->{kakaritype} eq 'P'){
		my $kakariSaki = $bps[$pos-1]->{kakarisaki};
		$bps[$pos-1]->{kakarisaki} = $bps[$kakariSaki]->{kakarisaki};
		print "> $kakariSaki\n";
	    }
	}

	## <意味有>が付いている形態素の代表表記を索引付け
	## 代表表記が複数個ある場合は代表表記の個数で割ってカウントする
	for(my $pos = 0; $pos < scalar(@bps); $pos++){
	    next unless(defined($bps[$pos]->{words}));

	    for(my $i = 0; $i < scalar(@{$bps[$pos]->{words}}); $i++){
		my $daihyou = $bps[$pos]->{words}->[$i];
		my $num_daihyou = scalar(@{$daihyou});
		for(my $j = 0; $j < $num_daihyou; $j++){
		    $freq{"$daihyou->[$j]"}->{freq} += (1 / $num_daihyou);
		    $freq{"$daihyou->[$j]"}->{pos} = $bps[$pos]->{w_poss}->[$i];
		    $freq{"$daihyou->[$j]"}->{absolute_pos} = $bps[$pos]->{ab_w_poss}->[$i];
		}
	    }
	}

	## <意味有>が付いている形態素間の係り受け関係を索引付け
	## 係り先・係り元に代表表記が複数個ある場合は、係り先・元の代表表記の個数の積で割ってカウントする
	for(my $pos = 0; $pos < scalar(@bps); $pos++){
	    my $kakariSaki = $bps[$pos]->{kakarisaki};
	    ## 基本句($bps[$pos])が文末(-1)なら
	    if($kakariSaki < 0){
		## <意味有>タグが付いている形態素が1つ
		if(scalar($bps[$pos]->{words}) < 2){
		    next;
		}else{
		    for(my $i = 0; $i < scalar(@{$bps[$pos]->{words}}); $i++){
			my $daihyou = $bps[$pos]->{words}->[$i];
			my $num_daihyou_moto = scalar(@{$daihyou});
			for(my $j = 0; $j < $num_daihyou_moto; $j++){
			    my $kakariSakiDaihyou;
			    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
			    ## ex)
			    ## 河野洋平
			    ## 河野->洋平
			    if($i + 1 < scalar(@{$bps[$pos]->{words}})){
				## 隣りの形態素に係る
				$kakariSakiDaihyou = $bps[$pos]->{words}->[$i+1];
			    }else{
				## 末尾の基本句なので終了(係り先なし)
				next;
			    }
			    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

			    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
			    for(my $k = 0; $k < $num_daihyou_saki; $k++){
				$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
				$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{pos} = $freq{$daihyou->[$j]}->{pos};
				$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{absolute_pos} = $freq{$daihyou->[$j]}->{absolute_pos};
			    }
			}
		    }
		}
		next;
	    }

	    next unless(defined($bps[$pos]->{words})); ## <意味有>タグが付いている形態素が基本句に無いなら

	    ## $pos番目の基本句に含まれる形態素と、その係り先の基本句(曖昧性がある場合は全て)
	    ## との組を索引付け
	    for(my $i = 0; $i < scalar(@{$bps[$pos]->{words}}); $i++){
		my $daihyou = $bps[$pos]->{words}->[$i];
		my $num_daihyou_moto = scalar(@{$daihyou});

		for(my $j = 0; $j < $num_daihyou_moto; $j++){
		    my $kakariSakiDaihyou;
		    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
		    ## ex)
		    ## 河野洋平と/行った。
		    ## 河野->洋平 洋平->行く
		    if($i + 1 < scalar(@{$bps[$pos]->{words}})){
			## 隣りの形態素に係る
			$kakariSakiDaihyou = $bps[$pos]->{words}->[$i+1];
		    }else{
			## 基本句全体で係っていた基本句に係る
			$kakariSakiDaihyou = $bps[$kakariSaki]->{words}->[0];
		    }

		    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

		    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
		    for(my $k = 0; $k < $num_daihyou_saki; $k++){
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{pos} = $freq{$daihyou->[$j]}->{pos};
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{absolute_pos} = $freq{$daihyou->[$j]}->{absolute_pos};
		    }
		}
	    }
	}
    }
    return \%freq;
}

sub makeIndexArrayfromKnpResult{
    my($this,$knp_result) = @_;

    my $pos = -1;
    my @index_array;
    foreach my $sent (split(/EOS\n/, $knp_result)){
	foreach my $line (split(/\n/,$sent)){
	    next if($line =~ /^\* \-?\d/);
	    next if($line =~ /^\+ (\-?\d+)/);
	    next if ($line =~ /^(\<|\@|EOS)/);

	    my @buff = ();
	    my @m = split(/\s+/, $line);
	    ## <意味有>タグが付与された形態素を索引付けする
	    if($line =~ /\<意味有\>/){
		next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		next if (&containsSymbols($m[2]) > 0); ## <記号>タグがついてない記号を削除

		my $word = $m[2];
		my @reps = ();
		## 代表表記の取得
		if($line =~ /代表表記:(.+?)\//){
		    $word = $1;
		}

		push(@reps, &toUpperCase_utf8($word));
		## 代表表記に曖昧性がある場合は全部保持する
		my $num_daihyou = scalar(@reps);
		while($line =~ /\<ALT(.+?)\>/){
		    $line = "$'";
		    if($1 =~ /代表表記:(.+?)\//){
			push(@reps, &toUpperCase_utf8($1));
		    }
		}

		my $num_daihyou = scalar(@reps);
		foreach my $w (@reps){
		    my $index_obj = {
			word => $w,
			freq => (1/$num_daihyou)
			};
		    push(@buff, $index_obj);
		}
	    }
	    next if(scalar(@buff) < 1);
	    push(@index_array, \@buff);
	} # end of foreach my $line (split(/\n/,$sent))
    }
    return \@index_array;
}

sub makeNgramIndex{
    my($this, $string, $N) = @_;
    ## make search queries.
    my $size = length($string);
    my %indexes = ();
    my $max = length($string);
    $max = $N if($max > $N);
    for(my $i = 0; $i < $size; $i++){
	for(my $j = 1; $j < $N + 1; $j++){
	    next if($i + $j > $size);
	    my $index = substr($string, $i, $j);
	    next if(length($index) < $max);
	    
	    $indexes{$index}->{score} = 0 unless(exists($indexes{$index}));
	    $indexes{$index}->{score} += 1;
	    $indexes{$index}->{pos} = $i;
	}
    }
    
    return \%indexes;
}

sub makeIndexfromIndexArray{
    my($this, $index_array, $window) = @_;
    my %index = ();
    for(my $i = 0; $i < scalar(@{$index_array}); $i++){
	foreach my $index_obj (@{$index_array->[$i]}){
	    my $word = $index_obj->{word};
	    my $freq = $index_obj->{freq};
	    my $L = $i - $window - 1;
	    my $R = $i + $window + 1;

# 	    $L = 0 if($L < 0);
# 	    $R = 0 if($R > scalar(@{$index_array}));
# 	    for(my $j = $L; $j < $i; $j++){
# #		my $dist = $j - $i;
# 		my $dist = $i - $j;
# 		next if($dist > $window);
#
# 		foreach my $p (@{$index_array->[$j]}){
# 		    my $word_p = $p->{word};
# 		    my $freq_p = $p->{freq};
#
# 		    my $key = $word_p . "##" . $word;
# #		    my $frq = ($freq * $freq_p) / $dist;
# 		    my $frq = 1;
# 		    $index{$key} = 0 unless(exists($index{$key}));
# 		    $index{$key} += $frq;
# 		}
#	    }

	    for(my $j = $i + 1; $j < $R; $j++){
		my $dist = $j - $i;
		next if($dist > $window);

		foreach my $p (@{$index_array->[$j]}){
		    my $word_p = $p->{word};
		    my $freq_p = $p->{freq};

		    my $key = $word . "##" . $word_p;
#		    my $frq = ($freq * $freq_p) / $dist;
		    my $frq = 1;
		    $index{$key} = {score => 0, pos => 0} unless(exists($index{$key}));
		    $index{$key}->{score} += $frq;
		    $index{$key}->{pos} = $i;
		}
	    }
	}
    }
    return \%index;
}

## 全角小文字アルファベット(utf8)を全角大文字アルファベットに変換(utf8)
sub toUpperCase_utf8(){
    my($str) = @_;
    my @cbuff = ();
    my @ch_codes = unpack("U0U*", $str);
    for(my $i = 0; $i < scalar(@ch_codes); $i++){
	my $ch_code = $ch_codes[$i];
	unless(0xff40 < $ch_code && $ch_code < 0xff5b){
	    push(@cbuff, $ch_code);
	}else{
	    my $uppercase_code = $ch_code - 0x0020;
	    push(@cbuff, $uppercase_code);
	}
    }
    return pack("U0U*",@cbuff);
}

## 平仮名、カタカナ、英数字以外を含んでいるかをチェック
sub containsSymbols(){
    my($text) = @_;
    my @ch_codes = unpack("U0U*", $text);
    for(my $i = 0; $i < scalar(@ch_codes); $i++){
	my $ch_code = $ch_codes[$i];
	## ひらがな   0x3041 < $ch_code && $ch_code < 0x3094
	## カタカナ   0x30A0 < $ch_code && $ch_code < 0x30FD
	## 漢字１     0x4DFF < $ch_code && $ch_code < 0x9FFF
	## 漢字２     0xF900 < $ch_code && $ch_code < 0xFA2F
	## 英数字(大) 0xFF0F < $ch_code && $ch_code < 0xFF3B
	## 英数字(小) 0xFF40 < $ch_code && $ch_code < 0xFF5B
	## 、。       $ch_code == 0xFF0C || $ch_code == 0xFF0E
	## 々〆       $ch_code == 0x3005 || $ch_code == 0x3006
	unless((0x3041 < $ch_code && $ch_code < 0x3094) ||
	       (0x30A0 < $ch_code && $ch_code < 0x30FD) ||
	       (0x4DFF < $ch_code && $ch_code < 0x9FFF) ||
	       (0xF900 < $ch_code && $ch_code < 0xFA2F) ||
	       (0xFF0F < $ch_code && $ch_code < 0xFF3B) ||
	       (0xFF40 < $ch_code && $ch_code < 0xFF5B) ||
	       $ch_code == 0xFF0C || $ch_code == 0xFF0E ||
	       $ch_code == 0x3005 || $ch_code == 0x3006){
#	    print "$text\n";
	    return 1;
	}
    }
    return 0;
}

1;
