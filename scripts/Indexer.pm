package Indexer;

###################################################################
# juman, knpの解析結果から索引付けする要素を抽出するモジュール
###################################################################

use strict;
use Encode;

our @EXPORT = qw(makeIndexfromJumanResult_utf8 makeIndexfromKnpResult_utf8);

## JUMANの解析結果から索引語を抽出する
sub makeIndexfromJumanResult_utf8(){
    my($juman_result) = @_;
    my %index = ();
    foreach my $line (split(/\n/,$juman_result)){
	next if ($line =~ /^(\<|EOS)/);

	## @の削除
	$line =~ s/^@\s+//;

	my @w = split(/\s+/, $line);
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
	$index{$word} = 0 unless(exists($index{$word}));
	$index{$word}++;
    }

    return \%index;
}

## KNPの解析結果から索引語と索引付け対象となる係り受け関係を抽出する
sub makeIndexfromKnpResult_utf8(){
    my($knp_result) = @_;

    my %freq;
    foreach my $sent (split(/EOS\n/, $knp_result)){
	my $pos = -1;
	my $kakariSaki = -1;
	my @bps = ();
	
	foreach my $line (split(/\n/,$sent)){
	    next if($line =~ /^\* \-?\d/);
	    
	    if($line =~ /^\+ (\-?\d+)/){
		$pos++;
		$kakariSaki = $1;
		@bps[$pos] = ();
		$bps[$pos] = {kakarisaki => $kakariSaki,
			      words => ()
			      };
	    }else{
		next if ($line =~ /^(\<|\@|EOS)/);
		
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
		    while($line =~ /\<ALT(.+?)\>/){
			$line = "$'";
			if($1 =~ /代表表記:(.+?)\//){
			    push(@reps, &toUpperCase_utf8($1));
			}
		    }
		    push(@{$bps[$pos]->{words}}, \@reps);
		}
	    } # end of else
	} # end of foreach my $line (split(/\n/,$sent))
	
	## <意味有>が付いている形態素の代表表記を索引付け
	for(my $i = 0; $i < scalar(@bps); $i++){
	    next unless(defined($bps[$i]->{words}));

	    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
		my $daihyou = $bps[$i]->{words}->[$j];
		for(my $k = 0; $k < scalar(@{$daihyou}); $k++){
		    $freq{"$daihyou->[$k]"}++;
		}
	    }
	}
	
# 	print STDERR "### " . scalar(@bps) . "\n";
# 	for(my $i = 0; $i < scalar(@bps); $i++){
# 	    print STDERR "$i @@@ ";
# 	    my $size = scalar($bps[$i]->{words});
# 	    foreach my $k (keys %{$bps[$i]}){
# 		print STDERR "$size $k=$bps[$i]->{$k},";
# 	    }
# 	    print STDERR "\n";
# 	}
	
	## <意味有>が付いている形態素間の係り受け関係を索引付け
	for(my $i = 0; $i < scalar(@bps); $i++){
	    my $kakariSaki = $bps[$i]->{kakarisaki};
	    ## 基本句が文末なら
	    if($kakariSaki < 0){
		## <意味有>タグが付いている形態素が1つ
		if(scalar($bps[$i]->{words}) < 2){
		    next;
		}else{
		    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
			my $daihyou = $bps[$i]->{words}->[$j];
			for(my $k = 0; $k < scalar(@{$daihyou}); $k++){
			    my $kakariSakiDaihyou;
			    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
			    ## ex)
			    ## 河野洋平
			    ## 河野->洋平
			    if($j + 1 < scalar(@{$bps[$i]->{words}})){
				## 隣りの形態素に係る
				$kakariSakiDaihyou = $bps[$i]->{words}->[$j+1];
			    }else{
				## 末尾の基本句なので終了(係り先なし)
				next;
			    }
			    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ
			    for(my $l = 0; $l < scalar(@{$kakariSakiDaihyou}); $l++){
				$freq{$daihyou->[$k] . "->" . $kakariSakiDaihyou->[$l]}++;
			    }
			}
		    }
		}
		next;
	    }
		    
	    next unless(defined($bps[$i]->{words})); ## <意味有>タグが付いている形態素が基本句に無いなら
	    
	    ## $i番目の基本句に含まれる形態素と、その係り先の基本句(曖昧性がある場合は全て)
	    ## との組を索引付け
	    for(my $j = 0; $j < scalar(@{$bps[$i]->{words}}); $j++){
		my $daihyou = $bps[$i]->{words}->[$j];

		for(my $k = 0; $k < scalar(@{$daihyou}); $k++){
		    my $kakariSakiDaihyou;
		    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
		    ## ex)
		    ## 河野洋平と/行った。
		    ## 河野->洋平 洋平->行く
		    if($j + 1 < scalar(@{$bps[$i]->{words}})){
			## 隣りの形態素に係る
			$kakariSakiDaihyou = $bps[$i]->{words}->[$j+1];
		    }else{
			## 基本句全体で係っていた基本句に係る
			$kakariSakiDaihyou = $bps[$kakariSaki]->{words}->[0];
		    }
			    
		    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ
		    for(my $l = 0; $l < scalar(@{$kakariSakiDaihyou}); $l++){
			$freq{$daihyou->[$k] . "->" . $kakariSakiDaihyou->[$l]}++;
		    }
		}
	    }
	}
    }
    return \%freq;
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
    return encode('utf8', pack("U0U*",@cbuff));
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
	    print "$text\n";
	    return 1;
	}
    }
    return 0;
}

1;
