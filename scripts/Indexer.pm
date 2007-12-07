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
    my($class, $opt) = @_;
    my $this = {
	absolute_pos => -1,
	handled_yomi => $opt->{handled_yomi}
    };

    if ($opt->{STOP_WORDS}) {
	$this->{STOP_WORDS} = $opt->{STOP_WORDS};
    }

    bless $this;
}

sub DESTROY {}

sub makeIndexfromSynGraph4Indexing {
    my($this, $syngraph) = @_;

    my @indice = ();
    # SynNode間の係り受け関係を管理する変数
    my %dpndInfo = ();
    # SynNodeの情報を管理する変数
    my %synNodes = ();
    foreach my $line (split(/\n/, $syngraph)) {
	## SynNode 間の係り受け関係の取得
	if ($line =~ /^!! /) {
	    my ($dumy, $id, $kakari, $midashi) = split(/ /, $line);
	    if ($kakari =~ /^(.+)(A|I|D|P)$/) {
		$dpndInfo{$id}->{kakariType} = $2;
		foreach my $kakariSakiID (split(/\//, $1)) {
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	} elsif ($line =~ /^! /) {
	    my ($dumy, $bnstId, $syn_node_str) = split(/ /, $line);

	    ## 複数の語からマップされている SynNode の場合は語の最後尾を出現位置とする
	    ## 「事務/所」と「オフィス」の場合、「オフィス」は「所」の部分に現れていると見なす
	    my $pos = ($bnstId =~ /,(\d+)$/) ? $1 : $bnstId;

	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $synid = $1;
		my $score = $2;
		my $features = $3;

		# 読みの削除
		$synid = $1 if ($synid =~ m!^([^/]+)/!);
		# <上位語>を削除
		$features = "$`$'" if ($features =~ /\<上位語\>/);
		# <下位語数:(数字)>を削除
		$features =~ s/<下位語数:\d+>//;

		# featureの順序を固定する
		my $tmp = join('>', sort {$a cmp $b} split('>', $features)) . '>' unless ($features eq '');

		my $syn_node = {
		    midashi => $synid . $features,
		    synId => $synid,
		    features => $features,
		    score => $score,
		    grpId => $bnstId,
		    pos => $pos,
		    absolute_pos => $this->{absolute_pos} + $pos + 1};
		push(@{$synNodes{$bnstId}}, $syn_node);
	    }
	}
    }

    # 索引の作成
    foreach my $bnstId (sort {$a <=> $b} keys %synNodes) {
	foreach my $synNode (@{$synNodes{$bnstId}}){
	    my $groupID = $synNode->{grpId};
	    my $score = $synNode->{score};
	    my $pos =  $synNode->{absolute_pos};
	    my $midashi = $synNode->{midashi};
	    my $index = {
		midashi => $midashi,
		rawstring => $midashi,
		group_id => $groupID,
		freq => $score,
		pos => $pos,
		isContentWord => 1
	    };
	    push(@indice, $index);

	    # 係り受け関係について索引を作成
	    my $kakariSakis = $dpndInfo{$bnstId}->{kakariSaki};
	    my $kakariType = $dpndInfo{$bnstId}->{kakariType};
	    foreach my $kakariSakiID (@{$kakariSakis}){
		my $kakariSakiNodes = $synNodes{$kakariSakiID};
		foreach my $kakariSakiNode (@{$kakariSakiNodes}){
		    my $index_dpnd = {
			midashi => ($midashi . '->' . $kakariSakiNode->{midashi}),
			rawstring => ($midashi . '->' . $kakariSakiNode->{midashi}),
			group_id => ($groupID . '/' . $kakariSakiNode->{grpId}),
			freq => ($score * $kakariSakiNode->{score}),
			pos => $pos,
			isContentWord => 1
		    };
		    push(@indice, $index_dpnd);
		}
	    }
	    $this->{absolute_pos} = $pos;
	}
    }

    return \@indice;
}


sub makeIndexfromSynGraph {
    my($this, $syngraph) = @_;

    my %dpndInfo = ();
    my %synNodes = ();
    foreach my $line (split(/\n/, $syngraph)) {
	if ($line =~ /^!! /) {
	    my($dumy, $id, $kakari, $midashi) = split(/ /, $line);
	    if ($kakari =~ /^(.+)(A|I|D|P)$/) {
		$dpndInfo{$id}->{kakariType} = $2;
		foreach my $kakariSakiID (split(/\//, $1)) {
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	} elsif($line =~ /^! /) {
	    my($dumy, $bnstId, $syn_node_str) = split(/ /, $line);
	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $sid = $1;
		my $score = $2;
		my $features = $3;

		# 読みの削除
		$sid = $1 if ($sid =~ m!^([^/]+)/!);
		$features = "$`$'" if ($features =~ /\<上位語\>/); # <上位語>を削除
		$features =~ s/<下位語数:\d+>//; # <下位語数:(数字)>を削除

		my $midashi = $sid . $features;
		my $syn_node = {midashi => $midashi,
				score => $score,
				grpId => $bnstId,
				pos => [],
				absolute_pos => []};

		push(@{$synNodes{$bnstId}}, $syn_node);
	    }
	}
    }

    my $pos = 0;
    my @freq = ();
    foreach my $id (sort {$a <=> $b} keys %synNodes) {
	foreach my $synNode (@{$synNodes{$id}}){
	    my $kakariSakis = $dpndInfo{$id}->{kakariSaki};
	    my $kakariType = $dpndInfo{$id}->{kakariType};
	    my $groupId = $synNode->{grpId};
	    my $score = $synNode->{score};

	    push(@freq, {midashi => $synNode->{midashi}});
	    $freq[-1]->{freq} = $score;
	    push(@{$freq[-1]->{pos}}, $pos);
	    $freq[-1]->{group_id} = $groupId;
	    $freq[-1]->{rawstring} = $synNode->{midashi};
	    $freq[-1]->{isContentWord} = 1;
	    
	    foreach my $kakariSakiID (@{$kakariSakis}){
		my $kakariSakiNodes = $synNodes{$kakariSakiID};
		foreach my $kakariSakiNode (@{$kakariSakiNodes}){
		    my $s = $score * $kakariSakiNode->{score};
		    push(@freq, {midashi => "$synNode->{midashi}->$kakariSakiNode->{midashi}"});
		    $freq[-1]->{freq} = $s;
		    push(@{$freq[-1]->{pos}}, $pos);
		    $freq[-1]->{group_id} = "$groupId\/$kakariSakiNode->{grpId}";
		    $freq[-1]->{rawstring} = "$synNode->{midashi}->$kakariSakiNode->{midashi}";
		    $freq[-1]->{isContentWord} = 1;
		}
	    }
	}
	$pos++;
    }

    return \@freq;
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

    my @freq;
    my %word2idx;
    foreach my $sent (split(/EOS\n/, $knp_result)){
#	$this->{absolute_pos}++;

	my $local_pos = -1;
	my $kakariSaki = -1;
	my $kakariType = undef;
	my @words = ();
	my @bps = ();
	foreach my $line (split(/\n/,$sent)){
	    next if ($line =~ /^\* \-?\d/);
	    next if ($line =~ /^!/);
	    next if ($line =~ /^S\-ID/);

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

		my $surf = $m[0];
		my $midashi = "$m[2]/$m[1]";
#		my $midashi = "$m[2]";
		my %reps = ();
		## 代表表記の取得
		if ($line =~ /\<代表表記:([^>]+)[a-z]?\>/) {
		    $midashi = $1;
#		    $midashi =~ s/\/.+//g;
		}

		next if (defined $this->{STOP_WORDS}{$midashi});

		$reps{&toUpperCase_utf8($midashi)} = 1;

		## 代表表記に曖昧性がある場合は全部保持する
		## ただし表記・読みが同一の代表表記は区別しない
		## ex) 日本 にっぽん 日本 名詞 6 地名 4 * 0 * 0 "代表表記:日本/にほん" <代表表記:日本/にほん><品曖><ALT-日本-にほん-日本-6-4-0-0-"代表表記:日本/にほん"> ...
		while ($line =~ /\<ALT(.+?)\>/) {
		    $line = "$'";
		    my $alt_cont = $1;
		    if ($alt_cont =~ /代表表記:(.+?)(?: |\")[a-z]?/) {
			my $midashi = $1;
			$reps{&toUpperCase_utf8($midashi)} = 1;
		    } elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
			my $midashi = "$3/$2";
			$reps{&toUpperCase_utf8($midashi)} = 1;
		    }
		}

		my @reps_array = sort keys %reps;
		my $word = {
		    surf => $surf,
		    reps => \@reps_array,
		    local_pos => $local_pos,
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

	my $idx = 0;
	## 代表表記が複数個ある場合は代表表記の個数で割ってカウントする
	for (my $pos = 0; $pos < scalar(@words); $pos++) {
	    my $surf = $words[$pos]->{surf};
	    my $reps = $words[$pos]->{reps};
	    my $size = scalar(@{$reps});
	    for (my $j = 0; $j < $size; $j++) {
		$word2idx{$reps->[$j]} = $idx++;

		push(@freq, {midashi => $reps->[$j]});
		$freq[-1]->{freq} += (1 / $size);
		push(@{$freq[-1]->{pos}}, $words[$pos]->{local_pos});
		push(@{$freq[-1]->{absolute_pos}}, $words[$pos]->{global_pos});
		$freq[-1]->{group_id} = $words[$pos]->{local_pos};
		$freq[-1]->{rawstring} = $reps->[$j];
		$freq[-1]->{surf} = $surf;
		$freq[-1]->{isContentWord} = $words[$pos]->{isContentWord};
	    }
	}

	## KNPの解析結果から単語インデックスのみを抽出したい場合
	return \@freq if $option->{no_dpnd};

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
				my $midashi = $reps->[$j] . "->" . $kakariSakiDaihyou->[$k];
				push(@freq, {midashi => $midashi});
				$freq[-1]->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
				push(@{$freq[-1]->{pos}}, @{$freq[$word2idx{$reps->[$j]}]->{pos}});
				push(@{$freq[-1]->{absolute_pos}}, @{$freq[$word2idx{$reps->[$j]}]->{absolute_pos}});
				$freq[-1]->{group_id} = "$freq[$word2idx{$reps->[$j]}]->{group_id}:$freq[$word2idx{$kakariSakiDaihyou->[$k]}]->{group_id}";
				$freq[-1]->{rawstring} = $midashi;
				$freq[-1]->{isContentWord} = 1;
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
			my $midashi = $daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k];
			push(@freq, {midashi => $midashi});
			$freq[-1]->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
			push(@{$freq[-1]->{pos}}, @{$freq[$word2idx{$daihyou->[$j]}]->{pos}});
			push(@{$freq[-1]->{absolute_pos}}, @{$freq[$word2idx{$daihyou->[$j]}]->{absolute_pos}});
			$freq[-1]->{group_id} = "$freq[$word2idx{$daihyou->[$j]}]->{group_id}:$freq[$word2idx{$kakariSakiDaihyou->[$k]}]->{group_id}";
			$freq[-1]->{rawstring} = $midashi;
			$freq[-1]->{isContentWord} = 1;
		    }
		}
	    }
	}
    }
    return \@freq;
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
