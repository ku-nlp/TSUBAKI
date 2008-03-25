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

    bless $this;
}

sub DESTROY {}

sub makeIndexfromSynGraph {
    my($this, $syngraph, $kihonkus) = @_;

    my %dpndInfo = ();
    my %synNodes = ();
    my $position= 0;
    my $knpbuf = '';
    my $first = 0;
    foreach my $line (split(/\n/, $syngraph)) {
	if ($line =~ /^!! /) {
	    my($dumy, $id, $kakari, $midasi) = split(/ /, $line);
	    if ($kakari =~ /^(.+)(A|I|D|P)$/) {
		$dpndInfo{$id}->{kakariType} = $2;
		$dpndInfo{$id}->{pos} = $position++;
		foreach my $kakariSakiID (split(/\//, $1)) {
		    push(@{$dpndInfo{$id}->{kakariSaki}}, $kakariSakiID);
		}
	    }
	} elsif ($line =~ /^! /) {
	    my ($dumy, $bnstIds, $syn_node_str) = split(/ /, $line);
	    my $fstring;
	    my $bnstId = $bnstIds;
	    foreach my $bid (split(/,/, $bnstIds)) {
		$fstring .= $kihonkus->[$bid]->fstring;
		$bnstId = $bid;
	    }
	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $sid = $1;
		my $score = $2;
		my $features = $3;

		# 読みの削除
		$sid = $1 if ($sid =~ m!^([^/]+)/!);
		$features = "$`$'" if ($features =~ /\<上位語\>/); # <上位語>を削除
		$features =~ s/<下位語数:\d+>//; # <下位語数:(数字)>を削除

		my $midasi = $sid . $features;
		my $syn_node = {midasi => $midasi,
				score => $score,
				grpId => $bnstId,
				fstring => $fstring,
				pos => [],
				NE => undef,
				question_type => undef,
				absolute_pos => []};

		if ($knpbuf =~ /(<NE:.+?>)/) {
		    $syn_node->{NE} = $1;
		}

		my $buf = $knpbuf;
		if ($buf =~ /(<[^>]+型>)/) {
		    if ($first > 0) {
			$syn_node->{question_type} .= $1;
			$buf = "$'";
		    }
		}

		push(@{$synNodes{$bnstId}}, $syn_node);
	    }
	} else {
	    if ($line =~ /^\+/) {
		$first = 1 if ($knpbuf =~ /(<[^>]+型>)/);
		$knpbuf = '';
	    } else {
		$knpbuf .= ($line . "\n");
	    }
	}
    }

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
		    next if ($kakariSakiNoKakaiSakiID eq '-1');
		    push(@new_kakariSaki, $kakariSakiNoKakaiSakiID);
		}
	    }
	    $dinfo->{kakariSaki} = \@new_kakariSaki;
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

	    push(@freq, {midasi => $synNode->{midasi}});
	    $freq[-1]->{freq} = $score;
	    push(@{$freq[-1]->{pos}}, $pos);
	    $freq[-1]->{group_id} = $groupId;
	    $freq[-1]->{midasi} = $synNode->{midasi};
	    $freq[-1]->{isContentWord} = 1;
	    $freq[-1]->{NE} = $synNode->{NE} if ($synNode->{NE});
	    $freq[-1]->{question_type} = $synNode->{question_type} if ($synNode->{question_type});
#	    $freq[-1]->{isBasicNode} = 1 if ($synNode->{midasi} !~ /s\d+/ && $synNode->{midasi} !~ /<[^>]+>/);
	    $freq[-1]->{isBasicNode} = 1 if ($synNode->{midasi} !~ /s\d+/);
	    $freq[-1]->{fstring} = $synNode->{fstring};
	    if (!defined $freq[-1]->{isBasicNode} && $freq[-1]->{NE}) {
		$freq[-1]->{fstring} .= "<削除::NEのSYNノード>";
	    }
	    
	    foreach my $kakariSakiID (@{$kakariSakis}){
		my $kakariSakiNodes = $synNodes{$kakariSakiID};
		foreach my $kakariSakiNode (@{$kakariSakiNodes}){
		    my $s = $score * $kakariSakiNode->{score};
		    push(@freq, {midasi => "$synNode->{midasi}->$kakariSakiNode->{midasi}"});
		    $freq[-1]->{freq} = $s;
		    push(@{$freq[-1]->{pos}}, $pos);
		    $freq[-1]->{group_id} = "$groupId\/$kakariSakiNode->{grpId}";
		    $freq[-1]->{midasi} = "$synNode->{midasi}->$kakariSakiNode->{midasi}";
		    $freq[-1]->{isContentWord} = 1;
		    $freq[-1]->{kakarimoto_fstring} = $synNode->{fstring};
		    $freq[-1]->{kakarisaki_fstring} = $kakariSakiNode->{fstring};
# 		    if ($freq[-1]->{midasi} !~ /s\d+/ &&
# 			$freq[-1]->{midasi} !~ /<[^>]+>/) {
# 			$freq[-1]->{isBasicNode} = 1
# 		    }
		    if ($freq[-1]->{midasi} !~ /s\d+/) {
			$freq[-1]->{isBasicNode} = 1
		    }
		}
	    }
	}
	$pos++;
    }

    return \@freq;
}

sub makeIndexFromKNPResult {
    my ($this, $result, $option) = @_;
    my $pos = $this->{absolute_pos};
    my $gid = 0;
    my @idx = ();
    foreach my $bnst ($result->bnst) {
	foreach my $kihonku ($bnst->tag) {
	    if (defined $kihonku->parent) {
		my $dpnd_idx = $this->get_dpnd_index($kihonku, $kihonku->parent, $option);
		foreach my $i (@$dpnd_idx) {
		    $i->{pos} = [$pos];
		    $i->{absolute_pos} = [$pos];
		    $i->{group_id} = $gid;
		}
		push(@idx, @$dpnd_idx);
	    }
	    $gid++;

	    foreach my $mrph ($kihonku->mrph) {
		my $words = [];
		if ($this->{genkei}) {
		    push(@$words, &get_genkei($mrph));
		} else {
		    $words = $this->get_repnames($mrph);
		}

		my $num_of_words = scalar(@$words);
		foreach my $word (@$words) {
		    push(@idx, {midasi => &toUpperCase_utf8($word)});
		    $idx[-1]->{group_id} = $gid;
		    $idx[-1]->{freq} = (1 / $num_of_words);
		    $idx[-1]->{isContentWord} = 1 if ($mrph->fstring =~ /<内容語|意味有>/);
		    $idx[-1]->{fstring} = $mrph->fstring;
		    $idx[-1]->{surf} = $mrph->midasi;
		    $idx[-1]->{pos} = [$pos];
		    $idx[-1]->{NE} = 1 if ($mrph->fstring =~ /<NE:/);
		    $idx[-1]->{absolute_pos} = [$pos];
		}
		$gid++;
		$pos++;
	    }
	}
    }

    $this->{absolute_pos} = $pos;
    return \@idx;
}

# 作り方→作る方
sub normalize_rentai {
    my ($this, $midasi, $fstring) = @_;

    if ($midasi =~ /(a|v)$/) {
	my ($daihyo) = ($fstring =~ /<品詞変更:.+?代表表記:(.+?)">/);
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
	    $reps{&toUpperCase_utf8($rep)} = 1;
	}
    } else {
	if ($this->{ignore_yomi}) {
	    $reps{&toUpperCase_utf8($mrph->midasi)} = 1;
	} else {
	    $reps{&toUpperCase_utf8($mrph->midasi) . "/" . $mrph->yomi} = 1;
	}
    }

    my @ret = keys %reps;
    return \@ret;
}

sub get_repnames2 {
    my ($this, $mrphs) = @_;

    my %reps = ();
    foreach my $mrph (@$mrphs) {
	next unless ($mrph->fstring =~ /<内容語|意味有>/);

	my ($repnames) = ($mrph->fstring =~ /<正規化代表表記.?:([^>]+)>/);
	if ($repnames) {
	    foreach my $rep (split(/\?/, $repnames)) {
		$rep =~ s/(.+?)\/.+?([a|v])?$/\1\2/ if ($this->{ignore_yomi});
		$rep = $this->normalize_rentai($rep, $mrph->fstring);
		$reps{&toUpperCase_utf8($rep)} = 1;
	    }
	} else {
	    if ($this->{ignore_yomi}) {
		$reps{&toUpperCase_utf8($mrph->midasi)} = 1;
	    } else {
		$reps{&toUpperCase_utf8($mrph->midasi) . "/" . $mrph->yomi} = 1;
	    }
	}
	last;
    }

    my @ret = keys %reps;
    return \@ret;
}

sub get_genkei {
    my ($mrph) = @_;

    my $genkei = &toUpperCase_utf8($mrph->genkei) . '*';

    return $genkei;
}

sub get_genkei2 {
    my ($mrphs) = @_;

    my $genkei;
    foreach my $mrph (@$mrphs) {
	next unless ($mrph->fstring =~ /<内容語|意味有>/);

	$genkei = &toUpperCase_utf8($mrph->genkei) . '*';
	last;
    }

    return $genkei;
}

sub get_dpnd_index {
    my ($this, $node1, $node2, $option) = @_;
    if ($node1->dpndtype eq 'P' && defined $node2->parent) {
	return $this->get_dpnd_index($node1, $node2->parent, $option);
    } else {
	my @idx = ();
	my @mrphs1 = $node1->mrph;
	my @mrphs2 = $node2->mrph;

	my $words1 = [];
	my $words2 = [];
	if ($this->{genkei}) {
	    push(@$words1, &get_genkei2(\@mrphs1));
	    push(@$words2, &get_genkei2(\@mrphs2));
	} else {
	    $words1 = $this->get_repnames2(\@mrphs1);
	    $words2 = $this->get_repnames2(\@mrphs2);
	}

	my $num_of_reps1 = scalar(@$words1);
	my $num_of_reps2 = scalar(@$words2);
	foreach my $rep1 (@$words1) {
	    foreach my $rep2 (@$words2) {
		my $midasi = sprintf("%s->%s", $rep1, $rep2);
		push(@idx, {midasi => $midasi});
		$idx[-1]->{freq} = 1 / ($num_of_reps1 * $num_of_reps2);
		$idx[-1]->{isContentWord} = 1;
	    }
	}
	return \@idx;
    }
}

## 全角小文字アルファベット(utf8)を全角大文字アルファベットに変換(utf8)
sub toUpperCase_utf8 {
    my($str) = @_;

    my $with_utf8_flag = utf8::is_utf8($str);
    if ($with_utf8_flag) {
	$str = encode('utf8', $str);
    }

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

    my $ret= pack("U0U*",@cbuff);
    if ($with_utf8_flag) {
	if (utf8::is_utf8($ret)) {
	    return $ret;
	} else {
	    return decode('utf8', $ret);
	}
    } else {
	return $ret;
    }
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

		# 読みの削除
		my $buf;
		foreach my $w (split(/\+/, $synid)) {
		    $w =~ s!^([^/]+)/!!;
		    $buf .= "$1+";
		}
		chop($buf);
		$synid = $buf;

		# 文法素性の削除
		$features =~ s/<可能>//;
		$features =~ s/<尊敬>//;
		$features =~ s/<受身>//;
		$features =~ s/<使役>//;
		$features =~ s/<反義語>//;
		$features =~ s/<上位語>//;

		# <下位語数:(数字)>を削除
		$features =~ s/<下位語数:\d+>//;

		# featureの順序を固定する
		my $tmp = join('>', sort {$a cmp $b} split('>', $features)) . '>' unless ($features eq '');

		my $syn_node = {
		    midasi => $synid . $features,
		    synId => $synid,
		    features => $features,
		    score => $score,
		    grpId => $bnstId,
		    pos => $pos,
		    absolute_pos => $pos};
		push(@{$synNodes{$bnstId}}, $syn_node);
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
	    my $groupID = $synNode->{grpId};
	    my $score = $synNode->{score};
	    my $pos =  $synNode->{absolute_pos};
	    my $midasi = $synNode->{midasi};
	    my $index = {
		midasi => $midasi,
		rawstring => $midasi,
		group_id => $groupID,
		score => $score,
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
			midasi => ($midasi . '->' . $kakariSakiNode->{midasi}),
			rawstring => ($midasi . '->' . $kakariSakiNode->{midasi}),
			group_id => ($groupID . '/' . $kakariSakiNode->{grpId}),
			score => ($score * $kakariSakiNode->{score}),
			pos => $pos,
			isContentWord => 1
		    };
		    push(@indice, $index_dpnd);
		}
	    }
	    # $this->{absolute_pos} = $pos;
	}
    }

    return \@indice;
}

1;
