package Indexer;

# $Id$

###################################################################
# Juman, KNP, SynGraphの解析結果から索引付けする要素を抽出するClass
###################################################################

use strict;
use utf8;
use Encode;

our @EXPORT = qw(makeIndexfromJumanResult makeIndexfromKnpResult makeNgramIndex);

sub new {
    my($class, $opt);
    my $this = {
	absolute_pos => -1,
	handled_yomi => $opt->{handled_yomi}
    };

    bless $this;
}

sub DESTROY {}

sub makeIndexfromSynGraph {
    my($this, $syngraph) = @_;

    my %freq = ();
    my %dpndInfo = ();
    my %synNodes = ();

    foreach my $line (split(/\n/, $syngraph)){
	if($line =~ /^!! /){
	    my($dumy, $id, $kakari, $midashi) = split(/ /, $line);
	    if($kakari =~ /^(.+)(A|I|D|P)$/){
		$dpndInfo{$id}->{kakariType} = $2;
		foreach my $kakariSakiID (split(/\//, $1)){
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	    
	}elsif($line =~ /^! /){
	    my($dumy, $bnstId, $syn_node_str) = split(/ /, $line);
	    if($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>(<[^>]+>)*$!){
		my $sid = $1;
		my $score = $2;
		my $features = $3;
		if($sid =~ m!^([^/]+)/!){
		    $sid = $1;
		}
		my $syn_node = {midashi => $sid . $features,
				score => $score,
				grpId => $bnstId,
				pos => [],
				absolute_pos => []};

		push(@{$synNodes{$bnstId}}, $syn_node);

		if ($features =~ /\<上位語\>/) {
		    $features = "$`$'";
		    my $syn_node = {midashi => $sid . $features,
				    score => $score,
				    grpId => $bnstId,
				    pos => [],
				    absolute_pos => []};
		    
		    push(@{$synNodes{$bnstId}}, $syn_node);
		}
	    }else{
#		print STDERR $line;
	    }
	}
    }

    my $pos = 0;
    foreach my $id (sort keys %synNodes){
	foreach my $synNode (@{$synNodes{$id}}){
	    my $kakariSakis = $dpndInfo{$id}->{kakariSaki};
	    my $kakariType = $dpndInfo{$id}->{kakariType};
	    my $groupId = $synNode->{grpId};
	    my $score = $synNode->{score};
	    
	    $freq{$synNode->{midashi}}->{freq} += $score;
# 	    push(@{$synNode->{midashi}->{pos}}, $pos);
# 	    push(@{$synNode->{midashi}->{absolute_pos}}, $pos);
	    $freq{$synNode->{midashi}}->{group_id} = $groupId;
	    $freq{$synNode->{midashi}}->{rawstring} = $synNode->{midashi};
	    $freq{$synNode->{midashi}}->{isContentWord} = 1;
	    
	    foreach my $kakariSakiID (@{$kakariSakis}){
		my $kakariSakiNodes = $synNodes{$kakariSakiID};
		foreach my $kakariSakiNode (@{$kakariSakiNodes}){
		    my $s = $score * $kakariSakiNode->{score};
		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{freq} += $s;
#		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{absolute_pos} = $pos;
#		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{grp_id} = "$groupId\/$kakariSakiNode->{grpId}";
		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{group_id} = "$groupId\/$kakariSakiNode->{grpId}";
		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{rawstring} = "$synNode->{midashi}->$kakariSakiNode->{midashi}";
		    $freq{"$synNode->{midashi}->$kakariSakiNode->{midashi}"}->{isContentWord} = 0;
		}
	    }
	}
	$pos++;
    }

    return \%freq;
}


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

## KNPの解析結果から索引語と索引付け対象となる係り受け関係を抽出する
sub makeIndexfromKnpResult {
    my($this,$knp_result,$option) = @_;

    my %freq;
    foreach my $sent (split(/EOS\n/, $knp_result)){
#	$this->{absolute_pos}++;

	my $local_pos = -1;
	my $kakariSaki = -1;
	my $kakariType = undef;
	my @words = ();
	my @bps = ();
	foreach my $line (split(/\n/,$sent)){
	    next if($line =~ /^\* \-?\d/);

 	    if($line =~ /^\+ (\-?\d+)([a-zA-Z])/){
		$kakariSaki = $1;
		$kakariType = $2;
		push(@bps, {kakarisaki => $kakariSaki,
			    kakaritype => $kakariType,
			    words => []
		     });
	    }else{
		next if ($line =~ /^(\<|\@|EOS)/);
		next if ($line =~ /^\# /);

		my @m = split(/\s+/, $line);

		$local_pos++;
		$this->{absolute_pos}++;

		my $midashi = "$m[2]/$m[1]";
		my @reps = ();
		## 代表表記の取得
		if ($line =~ /\<代表表記:([^>]+)\>/) {
		    $midashi = $1;
		}

		push(@reps, &toUpperCase_utf8($midashi));
		## 代表表記に曖昧性がある場合は全部保持する
		while ($line =~ /\<ALT(.+?)\>/) {
		    $line = "$'";
		    if ($1 =~ /代表表記:(.+?)\"/) {
			push(@reps, &toUpperCase_utf8($1));
		    }
		}

		my $word = {
		    reps => \@reps,
		    local_pos => $local_pos,
#		    string => $line,
		    global_pos => $this->{absolute_pos},
		    isContentWord => 0
		};

		push(@words, $word);

		if($line =~ /\<意味有\>/){
		    next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		    next if (&containsSymbols($m[2]) > 0); ## <記号>タグがついてない記号を削除

		    $word->{isContentWord} = 1;
		    push(@{$bps[-1]->{words}}, $word);
		}
	    } # end of else
	} # end of foreach my $line (split(/\n/,$sent))

	# 並列句において、係り元の係り先を、係り先の係り先に変更する
	# スプーンとフォークで食べる
	# スプーン->食べる、フォーク->食べる
	for(my $pos = scalar(@bps); $pos > 0; $pos--){
	    if($bps[$pos-1]->{kakaritype} eq 'P'){
		my $kakariSaki = $bps[$pos-1]->{kakarisaki};
		if($bps[$kakariSaki]->{kakarisaki} ne '-1'){
		    $bps[$pos-1]->{kakarisaki} = $bps[$kakariSaki]->{kakarisaki};
		}
	    }
	}

	## 代表表記が複数個ある場合は代表表記の個数で割ってカウントする
	for (my $pos = 0; $pos < scalar(@words); $pos++) {
	    my $reps = $words[$pos]->{reps};
	    my $size = scalar(@{$reps});
	    for (my $j = 0; $j < $size; $j++) {
		$freq{"$reps->[$j]"}->{freq} += (1 / $size);
		push(@{$freq{"$reps->[$j]"}->{pos}}, $words[$pos]->{local_pos});
		push(@{$freq{"$reps->[$j]"}->{absolute_pos}}, $words[$pos]->{global_pos});
		$freq{"$reps->[$j]"}->{group_id} = $words[$pos]->{local_pos};
		$freq{"$reps->[$j]"}->{rawstring} = $reps->[$j];
		$freq{"$reps->[$j]"}->{isContentWord} = $words[$pos]->{isContentWord};
	    }
	}

	## KNPの解析結果から単語インデックスのみを抽出したい場合
	return \%freq if $option->{no_dpnd};

	## <意味有>が付いている形態素間の係り受け関係を索引付け
	## 係り先・係り元に代表表記が複数個ある場合は、係り先・元の代表表記の個数の積で割ってカウントする
	for(my $pos = 0; $pos < scalar(@bps); $pos++){
	    my $kakariSaki = $bps[$pos]->{kakarisaki};
	    my $kakariMoto = $bps[$pos]->{words};
	    ## 基本句($bps[$pos])が文末(-1)なら
	    if($kakariSaki < 0){
		## <意味有>タグが付いている形態素が1つ
		if(scalar(@{$bps[$pos]->{words}}) < 2){
		    next;
		}else{
		    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
		    ## ex)
		    ## 河野洋平
		    ## 河野->洋平

		    for(my $i = 0; $i < scalar(@{$bps[$pos]->{words}}); $i++){
			my $word = $bps[$pos]->{words}->[$i];
			my $reps = $word->{reps};
			my $num_daihyou_moto = scalar(@{$reps});
			for(my $j = 0; $j < $num_daihyou_moto; $j++){
			    my $kakariSakiDaihyou;
			    if($i + 1 < scalar(@{$bps[$pos]->{words}})){
				## 隣りの形態素に係る
				$kakariSakiDaihyou = $bps[$pos]->{words}->[$i + 1]->{reps};
			    }else{
				## 末尾の基本句なので終了(係り先なし)
				next;
			    }
			    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

			    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
			    for(my $k = 0; $k < $num_daihyou_saki; $k++){
				$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
				push(@{$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{pos}}, @{$freq{$reps->[$j]}->{pos}});
				push(@{$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{absolute_pos}}, @{$freq{$reps->[$j]}->{absolute_pos}});
				$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{group_id} = $freq{$reps->[$j]}->{pos};
				$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{rawstring} = $reps->[$j] . "->" . $kakariSakiDaihyou->[$k];
				$freq{$reps->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{isContentWord} = 1;
			    }
			}
		    }
		}
		next;
	    }

	    next unless(defined($bps[$pos]->{words}->[0]->{reps})); ## <意味有>タグが付いている形態素が基本句に無いなら

	    ## $pos番目の基本句に含まれる形態素と、その係り先の基本句(曖昧性がある場合は全て)
	    ## との組を索引語として抽出
	    for(my $i = 0; $i < scalar(@{$bps[$pos]->{words}}); $i++){
		my $daihyou = $bps[$pos]->{words}->[$i]->{reps};
#		print STDERR encode('euc-jp', ($bps[$pos]->{words}->[$i]->{string})) . "\n";
		my $num_daihyou_moto = scalar(@{$daihyou});

		for(my $j = 0; $j < $num_daihyou_moto; $j++){
		    my $kakariSakiDaihyou;
		    ## 基本句に複数の<意味有>タグ付きの形態素がある場合は分解する
		    ## ex)
		    ## 河野洋平と/行った。
		    ## 河野->洋平 洋平->行く
		    if($i + 1 < scalar(@{$bps[$pos]->{words}})){
			## 隣りの形態素に係る
			$kakariSakiDaihyou = $bps[$pos]->{words}->[$i + 1]->{reps};
		    }else{
			## 基本句全体で係っていた基本句に係る
			$kakariSakiDaihyou = $bps[$kakariSaki]->{words}->[0]->{reps};
		    }

		    next unless(defined($kakariSakiDaihyou)); ## 係り先基本句に<意味有>タグが付いた形態素が無ければ

		    my $num_daihyou_saki = scalar(@{$kakariSakiDaihyou});
		    for(my $k = 0; $k < $num_daihyou_saki; $k++){
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
			push(@{$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{pos}}, @{$freq{$daihyou->[$j]}->{pos}});
			push(@{$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{absolute_pos}}, @{$freq{$daihyou->[$j]}->{absolute_pos}});
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{group_id} = $freq{$daihyou->[$j]}->{pos};
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{rawstring} = $daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k];
			$freq{$daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k]}->{isContentWord} = 1;
		    }
		}
	    }
	}
    }
    return \%freq;
}

sub makeNgramIndex {
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

## 全角小文字アルファベット(utf8)を全角大文字アルファベットに変換(utf8)
sub toUpperCase_utf8 {
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
sub containsSymbols {
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
