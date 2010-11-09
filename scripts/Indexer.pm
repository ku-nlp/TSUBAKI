package Indexer;

# $Id$

###################################################################
# Juman, KNP, SynGraphの解析結果から索引付けする要素を抽出するClass
###################################################################

# <内容語>，<準内容語>に対応．

use strict;
use utf8;
use Encode;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
use KNP;
use KNP::Result;

our $DEFAULT_MAX_NUM_OF_TERMS_FROM_SENTENCE = 1000;

sub new {
    my($class, $opt) = @_;
    my $this = {
	absolute_pos => 0,
	ignore_yomi => $opt->{ignore_yomi},
	genkei => $opt->{genkei},
	option => $opt
    };

    if ($opt->{STOP_WORDS}) {
	$this->{STOP_WORDS} = $opt->{STOP_WORDS};
    }

    if ($opt->{MAX_NUM_OF_TERMS_FROM_SENTENCE}) {
	$this->{MAX_NUM_OF_TERMS_FROM_SENTENCE} = $opt->{MAX_NUM_OF_TERMS_FROM_SENTENCE};
    } else {
	$this->{MAX_NUM_OF_TERMS_FROM_SENTENCE} = $DEFAULT_MAX_NUM_OF_TERMS_FROM_SENTENCE;
    }

    bless $this;
}

sub DESTROY {}


sub extractTerms {
    my ($this, $kihonkus, $surf, $position, $line, $synNodes, $lastBnstIds, $opt) = @_;

    my ($dumy, $bnstIds, $syn_node_str) = split(/ /, $line);

    my $fstring;
    my $bnstId = $bnstIds;
    foreach my $bid (split(/,/, $bnstIds)) {
	$fstring .= $kihonkus->[$bid];
	$bnstId = $bid;
    }

    next unless ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!);
    my ($sid, $score, $features) = ($1, $2, $3);

    # 読みの削除
    $sid = &remove_yomi($sid);

    # <上位語>を利用するかどうか
    next if ($features =~ /<上位語>/ && !$opt->{use_of_hypernym});

    # <反義語><否定>を利用するかどうか
    next if ($features =~ /<反義語>/ && $features =~ /<否定>/ && !$opt->{use_of_negation_and_antonym});

    # SYNノードを利用しない場合
    next if ($sid =~ /s\d+/ && $opt->{disable_synnode});

    # 文法素性の削除
    $features = &removeSyntacticFeatures($features);

    # <下位語数:(数字)>を削除
    $features =~ s/<下位語数:\d+>//;

    my $pos = $position + $this->{absolute_pos};
    my $midasi = lc($sid) . $features;

    # 音訓解消できてないターム（社/しゃ, 社/やしろ）が連続して登録されるのを防ぐ
    unless (defined $synNodes->{$bnstId}[-1] &&
	    $synNodes->{$bnstId}[-1]{midasi} eq $midasi &&
	    $synNodes->{$bnstId}[-1]{pos} == $pos) {
	my $syn_node = {
	    surf => $surf,
	    midasi => $midasi,
	    score => $score,
	    grpId => $bnstId,
	    fstring => $fstring,
	    pos => $pos,
	    _pos => $position,
	    question_type => undef,
	    absolute_pos => []};

	push (@{$synNodes->{$bnstId}}, $syn_node);
	$lastBnstIds->{$bnstId} = 1;
    }
}

sub remove_yomi {
    my ($text) = @_;

    my @buf;
    foreach my $word (split /\+/, $text) {
	my ($hyouki, $yomi) = split (/\//, $word);
	push (@buf, $hyouki);
    }

    return join ("+", @buf)
}

sub removeSyntacticFeatures {
    my ($midasi) = @_;

    $midasi =~ s/<可能>//;
    $midasi =~ s/<尊敬>//;
    $midasi =~ s/<受身>//;
    $midasi =~ s/<使役>//;

    return $midasi;
}

# 並列句において、係り元の係り先を、係り先の係り先に変更する
# スプーンとフォークで食べる
# スプーン->食べる、フォーク->食べる
sub processCoordinateStructure {
    my ($this, $dpndInfo) = @_;

    foreach my $id (sort {$dpndInfo->{$b}{pos} <=> $dpndInfo->{$a}{pos}} keys %$dpndInfo) {
	my $dinfo = $dpndInfo->{$id};
	if ($dinfo->{kakariType} eq 'P') {
	    my @new_kakariSaki = ();
	    foreach my $kakarisakiID (@{$dinfo->{kakariSaki}}) {
		my $kakariSakiInfo = $dpndInfo->{$kakarisakiID};
		foreach my $kakariSakiNoKakaiSakiID (@{$kakariSakiInfo->{kakariSaki}}) {
		    if ($kakariSakiNoKakaiSakiID eq '-1') {
			push(@new_kakariSaki, $kakarisakiID);
		    } else {
			push(@new_kakariSaki, $kakariSakiNoKakaiSakiID);
		    }
		}
	    }
	    $dinfo->{kakariSaki} = \@new_kakariSaki;
	}
    }
}

sub makeIndexfromSynGraph {
    my($this, $syngraph, $kihonkus, $poslist, $pos2info, $opt) = @_;

    if ($opt->{string_mode}) {
	return $this->makeIndexfromSynGraph4Indexing($syngraph, $opt);
    }

    my %dpndInfo = ();
    my %synNodes = ();
    my $position = 0;
    my $word_num = 0;
    my $knpbuf = '';
    my $first = 0;
    my $surf;
    my %lastBnstIds = ();
    my $NE_flag = undef;
    foreach my $line (split(/\n/, $syngraph)) {
	if ($line =~ /^\# /) {
	    next;
	} elsif ($line =~ /^!! /) {
	    my ($dumy, $id, $kakari, $midasi) = split(/ /, $line);
	    if ($kakari =~ /^(.+)(A|I|D|P)$/) {
		$dpndInfo{$id}->{kakariType} = $2;
		$dpndInfo{$id}->{pos} = $position + $this->{absolute_pos};
		foreach my $kakariSakiID (split(/\//, $1)) {
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	    ($surf) = ($midasi =~ /<見出し:([^>]+)>/);
	} elsif ($line =~ /^! /) {
	    # term（単語）の抽出
	    $this->extractTerms ($kihonkus, $surf, $position, $line, \%synNodes, \%lastBnstIds, $opt);
	} elsif ($line =~ /^\* /) {
	    %lastBnstIds = ();
	    $knpbuf .= ($line . "\n");
	} elsif ($line =~ /^EOS$/) {
	    $knpbuf .= ($line . "\n");
	} elsif ($line =~ /^S\-ID:\d+$/) {
	    $knpbuf .= ($line . "\n");
	} else {
	    $knpbuf .= ($line . "\n");
	    $position = $word_num if (index ($line, '<内容語>') > -1);
	    $word_num++ if ($line !~ /^\+/ && $line !~ /^\@/);

	    if ($line =~ m!情報:(.+?)/主辞:(.+?):!) {
		my ($info, $head, $pos, $log) = ($1, $2, $position + $this->{absolute_pos}, $&);
		$pos2info->{$pos}{midasi} = $head;
		$pos2info->{$pos}{log} = $log;
		foreach my $_info (split (/@/, $info)) {
		    if ($_info =~ /id=(\d+),off=(\d+),len=(\d+)/) {
			$pos2info->{$pos}{tid} = $1;
			push (@{$pos2info->{$pos}{offset}}, $2);
			push (@{$pos2info->{$pos}{length}}, $3);
		    }
		}
	    }
	}
    }
    $this->{absolute_pos} += $word_num;


    # 並列句において、係り元の係り先を、係り先の係り先に変更する
    # スプーンとフォークで食べる
    # スプーン->食べる、フォーク->食べる
    $this->processCoordinateStructure(\%dpndInfo);

    return $this->_makeTerms (\%synNodes, \%dpndInfo, $opt);
}

sub _makeTerms {
    my ($this, $synNodes, $dpndInfo, $opt) = @_;

    my @terms = ();
    foreach my $id (sort {$a <=> $b} keys %$synNodes) {
	foreach my $synNode (@{$synNodes->{$id}}){
	    my $kakariSakis = $dpndInfo->{$id}{kakariSaki};
	    my $kakariType = $dpndInfo->{$id}{kakariType};
	    my $groupId = $synNode->{grpId};
	    my $score = $synNode->{score};
	    my $pos = $synNode->{pos};
	    my $_pos = $synNode->{_pos};

	    # ?の連続からなる単語は削除
	    # next if ($synNode->{midasi} =~ /^\?+$/);

	    # 5桁以上の数字からなる単語は削除
	    # next if ($synNode->{midasi} =~ /[０|１|２|３|４|５|６|７|８|９]{5,}/);

#	    next if ($synNode->{midasi} =~ /s\d+/ && $synNode->{NE});


	    push(@terms, {midasi => $synNode->{midasi}});
	    $terms[-1]->{surf} = $synNode->{surf};
	    $terms[-1]->{freq} = $score;
	    $terms[-1]->{score} = $score;
	    $terms[-1]->{pos} = $pos;
	    $terms[-1]->{_pos} = $_pos;
	    $terms[-1]->{group_id} = $groupId;
	    $terms[-1]->{midasi} = $synNode->{midasi};
	    $terms[-1]->{isContentWord} = 1;
	    $terms[-1]->{NE} = $synNode->{NE};
	    $terms[-1]->{question_type} = $synNode->{question_type} if ($synNode->{question_type});
	    $terms[-1]->{isBasicNode} = 1 if ($synNode->{midasi} !~ /s\d+/);
	    $terms[-1]->{fstring} = $synNode->{fstring};

	    foreach my $kakariSakiID (@{$kakariSakis}){
		my $kakariSakiNodes = $synNodes->{$kakariSakiID};

		foreach my $kakariSakiNode (@{$kakariSakiNodes}){
		    # ?の連続からなる親または子を持つ係り受けは削除
# 		    next if ($kakariSakiNode->{midasi} =~ /^\?+$/ || $synNode->{midasi} =~ /^\?+$/);

# 		    # 5桁以上の数字からなる親または子を持つ係り受けは削除
# 		    next if ($kakariSakiNode->{midasi} =~ /[０|１|２|３|４|５|６|７|８|９]{5,}/ ||
# 			     $synNode->{midasi} =~ /[０|１|２|３|４|５|６|７|８|９]{5,}/);

 		    # SYNノードがらみの係り受けを使わない場合は next
 		    next if (!$opt->{use_of_syngraph_dependency} &&
 			     ($kakariSakiNode->{midasi} =~ /s\d+/ || $synNode->{midasi} =~ /s\d+/));

		    my $s = $score * $kakariSakiNode->{score};
		    push(@terms, {midasi => "$synNode->{midasi}->$kakariSakiNode->{midasi}"});
		    $terms[-1]->{freq} = $s;
		    $terms[-1]->{score} = $s;
		    $terms[-1]->{pos} = $pos;
		    $terms[-1]->{_pos} = $_pos;
		    $terms[-1]->{group_id} = "$groupId\/$kakariSakiNode->{grpId}";
		    $terms[-1]->{midasi} = "$synNode->{midasi}->$kakariSakiNode->{midasi}";
		    $terms[-1]->{isContentWord} = 1;
		    $terms[-1]->{kakarimoto_fstring} = $synNode->{fstring};
		    $terms[-1]->{kakarisaki_fstring} = $kakariSakiNode->{fstring};

		    if ($terms[-1]->{midasi} !~ /s\d+/) {
			$terms[-1]->{isBasicNode} = 1
		    }

		    if (scalar(@terms) > $this->{MAX_NUM_OF_TERMS_FROM_SENTENCE}) {
			$this->printErrorMessage("[SKIPPED THIS SENTENCE] Too much terms! (# of extracted tems > $this->{MAX_NUM_OF_TERMS_FROM_SENTENCE})");
			return ();
		    }
		}
	    }
	}
    }

    return \@terms;
}

sub makeIndexFromEnglishData {
    my ($this, $result, $option) = @_;

    my $gid = 0;
    my @terms = ();
    foreach my $line (split (/\n/, $result)) {
	my @midasis = split (" ", $line);
	$midasis[-1] .= "*";

	foreach my $midasi (@midasis) {
	    push(@terms, {midasi => $midasi});
	    $terms[-1]->{surf} = $midasi;
	    $terms[-1]->{freq} = 1;
	    $terms[-1]->{score} = 1;
	    $terms[-1]->{pos} = $this->{absolute_pos},
	    $terms[-1]->{group_id} = $gid;
	    $terms[-1]->{isContentWord} = 1;
	    $terms[-1]->{isBasicNode} = 1;
	}
	$this->{absolute_pos}++;
	$gid++;
    }

    return \@terms;
}

sub makeIndexFromCoNLLFormat {
    my ($this, $result, $option) = @_;

    my $gid = 0;
    my @terms = ();

    foreach my $line (split (/\n/, $result)) {
	my @data = split (/\t/, $line);

	my @midasis;
	push (@midasis, $data[1] . "*");
	push (@midasis, $data[2]);
	foreach my $midasi (@midasis) {
	    push(@terms, {midasi => $midasi});
	    $terms[-1]->{surf} = $midasi;
	    $terms[-1]->{freq} = 1;
	    $terms[-1]->{score} = 1;
	    $terms[-1]->{pos} = $this->{absolute_pos},
	    $terms[-1]->{group_id} = $gid;
	    $terms[-1]->{isContentWord} = 1;
	    $terms[-1]->{isBasicNode} = 1;
	}
	$this->{absolute_pos}++;
	$gid++;
    }

    return \@terms;
}

sub makeIndexFromKNPResult {
    my ($this, $result, $option) = @_;

    if ($option->{string_mode}) {
	return $this->makeIndexFromKNPResultString($result, $option);
    } else {
	require KNP;
	require KNP::Result;
	return $this->makeIndexFromKNPResultObject(new KNP::Result($result), $option);
    }
}


## KNPの解析結果から索引語と索引付け対象となる係り受け関係を抽出する
sub makeIndexFromKNPResultString {
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
		my $midasi = "$m[2]/$m[1]";
#		my $midasi = "$m[2]";
		my %reps = ();
		## 代表表記の取得
		if ($line =~ /\<代表表記:([^>]+)[a-z]?\>/) {
		    $midasi = $1;
#		    $midasi =~ s/\/.+//g;
		}

		next if (defined $this->{STOP_WORDS}{$midasi});

		$reps{&toLowerCase_utf8($midasi)} = 1;

		## 代表表記に曖昧性がある場合は全部保持する
		## ただし表記・読みが同一の代表表記は区別しない
		## ex) 日本 にっぽん 日本 名詞 6 地名 4 * 0 * 0 "代表表記:日本/にほん" <代表表記:日本/にほん><品曖><ALT-日本-にほん-日本-6-4-0-0-"代表表記:日本/にほん"> ...
		while ($line =~ /\<ALT(.+?)\>/) {
		    $line = "$'";
		    my $alt_cont = $1;
		    if ($alt_cont =~ /代表表記:(.+?)(?: |\")[a-z]?/) {
			my $midasi = $1;
			$reps{&toLowerCase_utf8($midasi)} = 1;
		    } elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
			my $midasi = "$3/$2";
			$reps{&toLowerCase_utf8($midasi)} = 1;
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

		if ($line =~ /(<内容語|意味有>)/) {
		    next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		    # next if (&containsSymbols($m[2]) > 0); ## <記号>タグがついてない記号を削除

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

		push(@freq, {midasi => $reps->[$j]});
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
				my $midasi = $reps->[$j] . "->" . $kakariSakiDaihyou->[$k];
				push(@freq, {midasi => $midasi});
				$freq[-1]->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
				push(@{$freq[-1]->{pos}}, @{$freq[$word2idx{$reps->[$j]}]->{pos}});
				push(@{$freq[-1]->{absolute_pos}}, @{$freq[$word2idx{$reps->[$j]}]->{absolute_pos}});
				$freq[-1]->{group_id} = "$freq[$word2idx{$reps->[$j]}]->{group_id}:$freq[$word2idx{$kakariSakiDaihyou->[$k]}]->{group_id}";
				$freq[-1]->{rawstring} = $midasi;
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
			my $midasi = $daihyou->[$j] . "->" . $kakariSakiDaihyou->[$k];
			push(@freq, {midasi => $midasi});
			$freq[-1]->{freq} += (1 / ($num_daihyou_saki * $num_daihyou_moto));
			push(@{$freq[-1]->{pos}}, @{$freq[$word2idx{$daihyou->[$j]}]->{pos}});
			push(@{$freq[-1]->{absolute_pos}}, @{$freq[$word2idx{$daihyou->[$j]}]->{absolute_pos}});
			$freq[-1]->{group_id} = "$freq[$word2idx{$daihyou->[$j]}]->{group_id}:$freq[$word2idx{$kakariSakiDaihyou->[$k]}]->{group_id}";
			$freq[-1]->{rawstring} = $midasi;
			$freq[-1]->{isContentWord} = 1;
		    }
		}
	    }
	}
    }
    return \@freq;
}

sub makeIndexFromSynGraphResultObject {
    my ($this, $result, $option) = @_;

    my $gid = 0;
    my $pos = 0;
    my @idxs = ();
    foreach my $bnst ($result->bnst) {
	foreach my $kihonku ($bnst->tag) {
	    next if ($kihonku->fstring =~ /クエリ削除語/);

	    unless ($option->{disable_dpnd}) {
		# 係り受けtermの抽出
		$this->extractDependencyTerms(\@idxs, $kihonku, \$gid, \$pos, $option);
	    }

	    # 単語に関するtermの抽出
	    if ($this->{genkei}) {
		$this->extractGenkeiTerms(\@idxs, $kihonku, \$gid, \$pos, $option);
		# $gid, $posは形態素単位
	    } else {
		$this->extractSynNodeTerms(\@idxs, $kihonku, \$gid, \$pos, $option);
		# $gid, $posは基本句単位
		$gid++;
		$pos++;
	    }
	}
    }

    # クエリの最後に出現している内容語の反対・否定表現を追加する
    $this->expandAntonymAndNegationTerms(\@idxs) if ($option->{antonym_and_negation_expansion});

    return \@idxs;
}

sub expandAntonymAndNegationTerms {
    my ($this, $idxs) = @_;

    my @buf;
    my @lastTerms = ();
    my $lastTermGroupID = $idxs->[-1]{group_id};
    my %midasiBuf;
    foreach my $i (reverse @$idxs) {
	last if ($i->{group_id} ne $lastTermGroupID);
	$midasiBuf{$i->{midasi}} = 1;
	push (@lastTerms, $i);
    }

    foreach my $Nd (@lastTerms) {
	# 構造体のコピー
	my $node;
	while (my ($k, $v) = each (%$Nd)) {
	    $node->{$k} = $v;
	}

	# 反義情報の削除
	$node->{midasi} =~ s/<反義語>//;

	# <否定>の付け変え
	if ($node->{midasi} =~ /<否定>/) {
	    $node->{midasi} =~ s/<否定>//;
	} else {
	    $node->{midasi} .= '<否定>';
	}
#	print $node->{midasi} . "\n";

	unless (exists $midasiBuf{$node->{midasi}}) {
	    $node->{additional_node} = 1;
	    push (@$idxs, $node);
	    $midasiBuf{$node->{midasi}} = 1;
	}
    }
}

sub addDependencyTerms {
    my ($this, $idxs, $terms, $kakarimoto, $kakarisaki, $pos, $option) = @_;

    # 係り受けtermの追加
    foreach my $idx (@{$terms}) {
	$idx->{pos} = ${$pos};
	$idx->{absolute_pos} = ${$pos};
	$idx->{isBasicNode} = 1;
	$idx->{group_id} = $kakarimoto->id . "/" . $kakarisaki->id;
	if ($idx->{fstring} =~ /クエリ必須係り受け/ || $option->{force_dpnd}) {
	    $idx->{requisite} = 1;
	    $idx->{optional}  = 0;
	} else {
	    $idx->{requisite} = 0;
	    $idx->{optional}  = 1;
	}
	push(@$idxs, $idx);
    }
}

sub generateDependencyTermsForParaType1 {
    my ($this, $idxs, $kakarimoto, $kakarisaki, $pos, $option) = @_;

    if (defined $kakarisaki->child) {
	foreach my $child ($kakarisaki->child) {

	    # 係り受け関係を追加する際、係り元のノード以前は無視する
	    # ex) 緑茶やピロリ菌
	    if ($child->dpndtype eq 'P' && $child->id > $kakarimoto->id) {
		my $terms = $this->get_dpnd_index($kakarimoto, $child, $option);
		$this->addDependencyTerms($idxs, $terms, $kakarimoto, $child, $pos, $option);

		# 子の子についても処理する
		$this->generateDependencyTermsForParaType1($idxs, $kakarimoto, $child, $pos, $option);
	    }
	}
    }
}

sub extractDependencyTerms {
    my ($this, $idxs, $kihonku, $gid, $pos, $option) = @_;

    if (defined $kihonku->parent) {
	my $kakarimoto = $kihonku;
	my $kakarisaki = $kihonku->parent;

	# 並列句の処理１
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 日本->政治, 日本->経済 の部分
	my $buf = $kakarisaki;
	if ($kakarimoto->dpndtype ne 'P') {
	    $this->generateDependencyTermsForParaType1($idxs, $kakarimoto, $kakarisaki, $pos, $option);
	}

	# 並列句の処理２
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 政治->正す, 経済->正す の部分
	my $buf = $kakarimoto;
	while ($buf->dpndtype eq 'P' && defined $kakarisaki->parent) {
	    $buf = $kakarisaki;
	    $kakarisaki = $kakarisaki->parent;
	}

	# 係り受けtermの取得
	my $terms = $this->get_dpnd_index($kakarimoto, $kakarisaki, $option);

	# 係り受けtermの追加
	$this->addDependencyTerms($idxs, $terms, $kakarimoto, $kakarisaki, $pos, $option);
	${$gid}++;
    }

    # テリック処理により生成される係り受けの追加
    if (defined $kihonku->parent && $kihonku->parent->fstring =~ /クエリ不要語/ && $kihonku->parent && $kihonku->parent->fstring =~ /テリック処理/ &&
	defined $kihonku->parent->parent && $kihonku->parent->parent->fstring !~ /クエリ削除語/) {
	foreach my $idx (@{$this->get_dpnd_index($kihonku, $kihonku->parent->parent, $option)}) {
	    $idx->{pos} = ${$pos};
	    $idx->{absolute_pos} = ${$pos};
	    $idx->{isBasicNode} = 1;
#	    $idx->{group_id} = $kihonku->id . "/" . $kihonku->parent->parent->id;
	    $idx->{group_id} = $gid + 1000;
	    $idx->{requisite} = 0;
	    $idx->{optional}  = 1;

	    push(@$idxs, $idx);
	}
	${$gid}++;
    }
}

sub extractGenkeiTerms {
    my ($this, $idxs, $kihonku, $gid, $pos, $option) = @_;

    foreach my $mrph ($kihonku->mrph) {
	$this->{absolute_pos}++;
	next if ($option->{content_word_only} && $mrph->fstring !~ /<内容語|意味有>/);

	my $words = [];
	push(@$words, &get_genkei($mrph));

	my $num_of_words = scalar(@$words);
	foreach my $word (@$words) {
	    push(@$idxs, {midasi => &toLowerCase_utf8($word)});
	    $idxs->[-1]{group_id} = $$gid;
	    $idxs->[-1]{freq} = (1 / $num_of_words);
	    $idxs->[-1]{score} = (1 / $num_of_words);
	    $idxs->[-1]{isContentWord} = ($mrph->fstring =~ /<内容語>/) ? 1 : 0;
	    $idxs->[-1]{fstring} = $mrph->fstring;
	    $idxs->[-1]{surf} = $mrph->midasi;
	    $idxs->[-1]{pos} = $$pos;
	    $idxs->[-1]{NE} = 1 if ($mrph->fstring =~ /<NE:/);
	    $idxs->[-1]{absolute_pos} = $$pos;
	    $idxs->[-1]{requisite} = 1;
	    $idxs->[-1]{optional} = 0;
	}
	($$gid)++;
	($$pos)++;
    }
}

sub extractSynNodeTerms {
    my ($this, $idxs, $kihonku, $gid, $pos, $option) = @_;

    my $POS;
    my $katsuyou;
    foreach my $m (reverse $kihonku->mrph) {
	if ($m->fstring =~ /<内容語>/) {
	    $POS = sprintf ("%s:%s", $m->hinsi, $m->bunrui);
	    $katsuyou = sprintf ("%s:%s", $m->katuyou1, $m->katuyou2);
	}
    }

    # 単語・同義語・同義句インデックスの抽出
    foreach my $synnodes ($kihonku->synnodes) {
	foreach my $synnode ($synnodes->synnode) {
	    my $synid = $synnode->synid;
	    my $synid_with_yomi = $synid;
	    my $score = $synnode->score;
	    my $features = $synnode->feature;

	    # 読みの削除
	    my $buf;
	    $synid = &remove_yomi($synid);

	    # <上位語>を利用するかどうか
	    if ($features =~ /<上位語>/) {
		if ($option->{use_of_hypernym}) {
		    $features =~ s/<上位語>//g;
		} else {
		    next;
		}
	    }

	    # <反義語><否定>を利用するかどうか
	    if ($features =~ /<反義語>/ && $features =~ /<否定>/) {
		next unless ($option->{use_of_negation_and_antonym});
	    }

	    # SYNノードを利用しない場合
	    next if ($synid =~ /s\d+/ && $option->{disable_synnode});

	    # 文法素性の削除
	    $features =~ s/<(可能|尊敬|受身|使役)>//g;

	    # <下位語数:(数字)>を削除
	    $features =~ s/<下位語数:\d+>//g;

	    push(@$idxs, {midasi => lc($synid) . $features});
	    $idxs->[-1]{midasi_with_yomi} = $synid_with_yomi;
	    $idxs->[-1]{group_id} = $kihonku->id;
	    $idxs->[-1]{freq} = $score;
	    $idxs->[-1]{isContentWord} = 1;
	    $idxs->[-1]{isBasicNode} = ($synid =~ /s\d+/) ? 0 : 1;
	    $idxs->[-1]{fstring} = $kihonku->fstring;
	    $idxs->[-1]{surf} = $synnodes->midasi;
	    $idxs->[-1]{pos} = $$pos;
	    $idxs->[-1]{katsuyou} = $katsuyou;
	    $idxs->[-1]{POS} = $POS;
	    $idxs->[-1]{NE} = ($kihonku->fstring =~ /<NE(内)?:.+?>/) ? $& : 0;

	    if ($kihonku->fstring =~ /クエリ不要語/) {
		$idxs->[-1]{requisite} = 0;
		$idxs->[-1]{optional}  = 1;
	    } else {
		$idxs->[-1]{requisite} = 1;
		$idxs->[-1]{optional}  = 0;
	    }
	}
    }
}

sub makeIndexFromKNPResultObject {
    my ($this, $result, $option) = @_;
    my $pos = $this->{absolute_pos};
    my $_pos = 0;
    my $gid = 0;
    my @idx = ();
    foreach my $bnst ($result->bnst) {
	foreach my $kihonku ($bnst->tag) {
	    if (defined $kihonku->parent && !$option->{disable_dpnd}) {
		$this->extractDependencyTerms(\@idx, $kihonku, \$gid, \$pos, $option);
	    }
	    $gid++;

	    foreach my $mrph ($kihonku->mrph) {
		$this->{absolute_pos}++;
		next if ($option->{content_word_only} && $mrph->fstring !~ /<内容語|意味有>/);

		my $words = [];
		if ($this->{genkei}) {
		    push(@$words, &get_genkei($mrph));
		} else {
		    $words = $this->get_repnames($mrph);
		}

		my $num_of_words = scalar(@$words);
		foreach my $word (@$words) {
		    $word = &remove_yomi($word) if ($this->{ignore_yomi});

		    push(@idx, {midasi => &toLowerCase_utf8($word)});
		    $idx[-1]->{group_id} = $gid;
		    $idx[-1]->{freq} = (1 / $num_of_words);
		    $idx[-1]->{score} = (1 / $num_of_words);
		    $idx[-1]->{isContentWord} = ($mrph->fstring =~ /<内容語|意味有>/) ? 1 : 0;
		    $idx[-1]->{isBasicNode} = 1;
		    $idx[-1]->{fstring} = $mrph->fstring;
		    $idx[-1]->{surf} = $mrph->midasi;
		    $idx[-1]->{pos} = $pos;
		    $idx[-1]->{_pos} = $_pos;
		    $idx[-1]->{NE} = 1 if ($mrph->fstring =~ /<NE:/);
		    $idx[-1]->{absolute_pos} = $pos;
		    $idx[-1]->{requisite} = 1;
		    $idx[-1]->{optional} = 0;
		}
		$gid++;
		$pos++;
		$_pos++
	    }
	}
    }
    return \@idx;
}

# 作り方→作る方
sub normalize_rentai {
    my ($this, $midasi, $fstring) = @_;

    if ($midasi =~ /(a|v)$/) {
	my ($daihyo) = ($fstring =~ /<品詞変更:.+?代表表記:(.+?)">/); #"
	($daihyo) = ($fstring =~ /<代表表記変更:(.+?)>/) unless ($daihyo);
	my ($daihyo_kanji, $daihyo_yomi) = split(/\//, $daihyo);
	if ($daihyo =~ /^\p{Hiragana}+\/?$/) {
	    $midasi = $daihyo;
	} else {
	    if ($this->{ignore_yomi}) {
		$midasi =~ s/\p{Hiragana}*?[a|v]$//; # 送り仮名の削除
		my ($kanji, $kana) = ($daihyo =~ /(\p{Han}+)(\p{Hiragana}+)/);
		$midasi .= $kana;
	    } else {
		$midasi =~ s/\p{Hiragana}+?\/.+([a|v]?)$/\1/; # 送り仮名／読み仮名無視
		my ($kanji, $kana) = ($daihyo =~ /(\p{Han}+)(\p{Hiragana}+)/);
		$midasi = ($midasi . $kana . "/" . $daihyo_yomi);
	    }
	}
    }

    return $midasi;
}

sub get_repnames {
    my ($this, $mrph) = @_;

    my ($repnames) = ($mrph->fstring =~ /<正規化代表表記.?:([^>]+)>/);
    my %reps = ();
    if ($repnames) {
	foreach my $rep (split(/\?/, $repnames)) {
	    $rep =~ s/(.+?)\/.+?([a|v])?$/\1\2/ if ($this->{ignore_yomi});
	    $rep = $this->normalize_rentai($rep, $mrph->fstring);
	    $reps{&toLowerCase_utf8($rep)} = 1;
	}
    } else {
	if ($this->{ignore_yomi}) {
	    $reps{&toLowerCase_utf8($mrph->midasi)} = 1;
	} else {
	    $reps{&toLowerCase_utf8($mrph->midasi) . "/" . $mrph->yomi} = 1;
	}
    }

    my @ret = keys %reps;
    return \@ret;
}

sub get_repnames2 {
    my ($this, $kihonku) = @_;

    my %reps = ();
    my $hasSyngraphAnnotation = $kihonku->synnodes;
    # SYNGRAPHの解析結果から抽出
    if ($hasSyngraphAnnotation) {
	foreach my $synnodes ($kihonku->synnodes) {
	    foreach my $synnode ($synnodes->synnode) {
		my $midasi = $synnode->synid;
		next if ($midasi =~ /s\d+/);
		next if ($synnode->feature =~ /<[^>]+>/);

		# 読みの削除
		$midasi = &remove_yomi($midasi)	if ($this->{ignore_yomi});

		$reps{&toLowerCase_utf8($midasi)} = 1;
	    }
	}
    }
    # KNPの解析結果から抽出
    else {
	foreach my $mrph ($kihonku->mrph) {
	    next unless ($mrph->fstring =~ /<内容語|意味有>/);

	    if ($mrph->fstring =~ /<可能動詞:(.+?)>/) {
		my $midasi = $1;
		if ($this->{ignore_yomi}) {
		    $midasi =~ s/(.+?)\/.+?([a|v])?$/\1\2/;
		    $midasi = $this->normalize_rentai($midasi, $mrph->fstring);
		    $reps{&toLowerCase_utf8($midasi)} = 1;
		} else {
		    $reps{&toLowerCase_utf8($midasi) . "/" . $mrph->yomi} = 1;
		}
	    } else {
		my ($repnames) = ($mrph->fstring =~ /<正規化代表表記.?:([^>]+)>/);
		if ($repnames) {
		    foreach my $rep (split(/\?/, $repnames)) {
			$rep =~ s/(.+?)\/.+?([a|v])?$/\1\2/ if ($this->{ignore_yomi});
			$rep = $this->normalize_rentai($rep, $mrph->fstring);
			$reps{&toLowerCase_utf8($rep)} = 1;
		    }
		} else {
		    if ($this->{ignore_yomi}) {
			$reps{&toLowerCase_utf8($mrph->midasi)} = 1;
		    } else {
			$reps{&toLowerCase_utf8($mrph->midasi) . "/" . $mrph->yomi} = 1;
		    }
		}
	    }
	    last;
	}
    }

    my @ret = sort keys %reps;
    return \@ret;
}

sub remove_yomi {
    my ($midasi) = @_;

    my @buf;
    foreach my $w (split(/\+/, $midasi)) {
	my ($hyouki, $yomi) = split(/\//, $w);
	# $hyouki .= $1 if ($yomi =~ /([a|v])$/);
	push (@buf, ${hyouki});
    }

    return  join ('+', @buf);
}


sub get_genkei {
    my ($mrph) = @_;

    my $genkei = &toLowerCase_utf8($mrph->midasi) . '*';

    return $genkei;
}

sub get_genkei2 {
    my ($mrphs) = @_;

    my $genkei;
    foreach my $mrph (@$mrphs) {
	next unless ($mrph->fstring =~ /<内容語|意味有>/);

	$genkei = &toLowerCase_utf8($mrph->midasi) . '*';
	last;
    }

    return $genkei;
}

sub get_dpnd_index {
    my ($this, $kihonku1, $kihonku2, $option) = @_;

    return [] if ($kihonku2->fstring =~ /クエリ削除語/);

    my @idx = ();
    my $words1 = [];
    my $words2 = [];
    if ($this->{genkei}) {
	my @mrphs1 = $kihonku1->mrph;
	my @mrphs2 = $kihonku2->mrph;
	push(@$words1, &get_genkei2(\@mrphs1));
	push(@$words2, &get_genkei2(\@mrphs2));
    } else {
	$words1 = $this->get_repnames2($kihonku1);
	$words2 = $this->get_repnames2($kihonku2);
    }

    my $num_of_reps1 = scalar(@$words1);
    my $num_of_reps2 = scalar(@$words2);
    foreach my $rep1 (@$words1) {
	foreach my $rep2 (@$words2) {
	    my $midasi = sprintf("%s->%s", $rep1, $rep2);
	    push(@idx, {midasi => $midasi});
	    $idx[-1]->{freq} = 1;# / ($num_of_reps1 * $num_of_reps2);
	    $idx[-1]->{score} = 1;# / ($num_of_reps1 * $num_of_reps2);
	    $idx[-1]->{isContentWord} = 1;
	    $idx[-1]->{fstring} = $kihonku1->fstring;
	}
    }

    return \@idx;
}

## 全角小文字アルファベット(utf8)を全角大文字アルファベットに変換(utf8)
sub toLowerCase_utf8 {
    my($str) = @_;
    return lc($str);
}

sub makeIndexfromSynGraph4Indexing {
    my($this, $syngraph) = @_;

    my @indice = ();
    # SynNode間の係り受け関係を管理する変数
    my %dpndInfo = ();
    # SynNodeの情報を管理する変数
    my %synNodes = ();
    my $position = 0;
    my $word_num = 0;
    foreach my $line (split(/\n/, $syngraph)) {
	## SynNode 間の係り受け関係の取得
	if ($line =~ /^!! /) {
	    my ($dumy, $id, $kakari, $midasi) = split(/ /, $line);
	    if ($kakari =~ /^(.+)(A|I|D|P)$/) {
		$dpndInfo{$id}->{kakariType} = $2;
		$dpndInfo{$id}->{pos} = $position + $this->{absolute_pos};
		foreach my $kakariSakiID (split(/\//, $1)) {
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	} elsif ($line =~ /^! /) {
	    my ($dumy, $bnstId, $syn_node_str) = split(/ /, $line);

	    ## 複数の語からマップされている SynNode の場合は語の最後尾を出現位置とする
	    ## 「事務/所」と「オフィス」の場合、「オフィス」は「所」の部分に現れていると見なす
	    my $pos = $position + $this->{absolute_pos}; # ($bnstId =~ /,(\d+)$/) ? $1 : $bnstId;

	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $synid = $1;
		my $score = $2;
		my $features = $3;
		my $synid_w_yomi = $synid;

		# 読みの削除
		my $buf;
		foreach my $w (split(/\+/, $synid)) {
		    $w =~ s!^([^/]+)/!!;
		    $buf .= "$1+";
		}
		chop($buf);
		$synid = uc($buf);

		# 文法素性の削除
		$features =~ s/<可能>//;
		$features =~ s/<尊敬>//;
		$features =~ s/<受身>//;
		$features =~ s/<使役>//;
		$features =~ s/<上位語>//;

		# <下位語数:(数字)>を削除
		$features =~ s/<下位語数:\d+>//;

		# featureの順序を固定する
		my $tmp = join('>', sort {$a cmp $b} split('>', $features)) . '>' unless ($features eq '');

		my $syn_node = {
		    midasi => lc($synid) . $features,
		    synId => $synid,
		    features => $features,
		    score => $score,
		    grpId => $bnstId,
		    pos => $pos,
		    absolute_pos => $pos};
		push(@{$synNodes{$bnstId}}, $syn_node);

# 		if ($syn_node->{midasi} !~ /s\d+/) {
# 		    my $syn_node = {
# 			midasi => $synid_w_yomi . $features,
# 			synId => $synid_w_yomi,
# 			features => $features,
# 			score => $score,
# 			grpId => $bnstId,
# 			pos => $pos,
# 			with_yomi => 1,
# 			absolute_pos => $pos};
# 		    push(@{$synNodes{$bnstId}}, $syn_node);
# 		}
	    }
	} elsif ($line =~ /^\+ /) {
	} elsif ($line =~ /^\* /) {
	} elsif ($line =~ /^EOS$/) {
	} elsif ($line =~ /^S\-ID:\d+$/) {
	} else {
	    $position = $word_num if ($line =~ /<内容語|意味有>/);
	    $word_num++;
	}
    }
    $this->{absolute_pos} += $word_num;

    # 並列句において、係り元の係り先を、係り先の係り先に変更する
    # スプーンとフォークで食べる
    # スプーン->食べる、フォーク->食べる
    foreach my $id (sort {$dpndInfo{$b}->{pos} <=> $dpndInfo{$a}->{pos}} keys %dpndInfo) {
	my $dinfo = $dpndInfo{$id};
	if ($dinfo->{kakariType} eq 'P') {
	    my @new_kakariSaki = ();
	    foreach my $kakarisakiID (@{$dinfo->{kakariSaki}}) {
		my $kakariSakiInfo = $dpndInfo{$kakarisakiID};
		foreach my $kakariSakiNoKakaiSakiID (@{$kakariSakiInfo->{kakariSaki}}) {
		    if ($kakariSakiNoKakaiSakiID eq '-1') {
			push(@new_kakariSaki, $kakarisakiID);
		    } else {
			push(@new_kakariSaki, $kakariSakiNoKakaiSakiID);
		    }
		}
	    }
	    $dinfo->{kakariSaki} = \@new_kakariSaki;
	}
    }

    # 索引の作成
    foreach my $bnstId (sort {$a <=> $b} keys %synNodes) {
	foreach my $synNode (@{$synNodes{$bnstId}}){
	    next if ($synNode->{with_yomi});

	    my $groupID = $synNode->{grpId};
	    my $score = $synNode->{score};
	    my $pos =  $synNode->{absolute_pos};
	    my $midasi = $synNode->{midasi};
	    my $index = {
		midasi => lc($midasi),
		rawstring => $midasi,
		group_id => $groupID,
		score => $score,
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
		    next if ($kakariSakiNode->{with_yomi});

		    my $index_dpnd = {
			midasi => lc($midasi . '->' . $kakariSakiNode->{midasi}),
			rawstring => ($midasi . '->' . $kakariSakiNode->{midasi}),
			group_id => ($groupID . '/' . $kakariSakiNode->{grpId}),
			score => ($score * $kakariSakiNode->{score}),
			freq => $score,
			pos => $pos,
			isContentWord => 1
		    };
		    push(@indice, $index_dpnd);

		    if (scalar(@indice) > $this->{MAX_NUM_OF_TERMS_FROM_SENTENCE}) {
			$this->printErrorMessage("[SKIPPED THIS SENTENCE] Too much terms! (# of extracted tems > $this->{MAX_NUM_OF_TERMS_FROM_SENTENCE})");
			return ();
		    }
		}
	    }
	    # $this->{absolute_pos} = $pos;
	}
    }

    return \@indice;
}


sub printErrorMessage {
    my ($this, $msg) = @_;

    print STDERR $msg . "\n";
}

1;
