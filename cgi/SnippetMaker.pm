package SnippetMaker;

# $Id$

use strict;
use Encode qw(encode decode from_to);
use utf8;

use KNP::Result;
use Indexer;
use Configure;
use StandardFormatData;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $CONFIG = Configure::get_instance();
my $NUM_OF_CHARS_IN_HEADER = 100;

sub extract_sentences_from_ID {
    my($query, $did_w_version, $opt) = @_;

    my $dir_prefix = $CONFIG->{DIR_PREFIX_FOR_SFS_W_SYNGRAPH};
    my $xmlfile;
    if ($CONFIG->{IS_NICT_MODE}) {
	my ($did) = ($did_w_version =~ /(^\d+)/);
	$xmlfile = sprintf("%s/x%04d/x%07d/%s.xml.gz", $dir_prefix, $did / 1000000, $did / 1000, $did_w_version);
    } else {
	my $did = $did_w_version;
	# $xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $dir_prefix, $did / 1000000, $did / 10000, $did);
	$xmlfile = sprintf("%s/%s.xml.gz", $dir_prefix, $did);
    }
    return &extract_sentences_from_standard_format($query, $xmlfile, $opt);
}

sub extract_sentences_from_standard_format {
    my($query, $xmlfile, $opt) = @_;

    if ($opt->{verbose}) {
	print "extract from $xmlfile.\n";
	print "option:\n";
	print Dumper($opt) . "\n";
    }

    if ($opt->{z}) {
	open(READER,"zcat $xmlfile |") or die "$!";
    } else {
	open(READER, $xmlfile) or die "$!";
    }
    binmode(READER, ':utf8');


    my $content;
    if ($opt->{extract_from_abstract_only}) {
	while (<READER>) {
	    last  if ($_ =~ /<\/Header>/);
	    $content .= $_;
	}
	close(READER);

	return &extract_sentences_from_abstract($query, $content, $opt);
    } else {
	while (<READER>) {
	    $content .= $_;
	}
	close(READER);

	if ($opt->{kwic}) {
	    return &extract_sentences_from_content_for_kwic($query, $content, $opt);
	} else {
	    # Title, Keywords, Description から重要文を抽出しない
	    if ($opt->{start} > $NUM_OF_CHARS_IN_HEADER) {
		return &extract_sentences_from_content_using_position($query, $content, $opt);
	    } else {
		return &extract_sentences_from_content($query, $content, $opt);
	    }
	}
    }
}

sub extract_sentences_from_content_using_position {
    my ($query, $content, $opt) = @_;

    # 前後width語を重要文の抽出範囲とする
    my $width = ($CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET} - ($opt->{end} - $opt->{start})) / 2;
    my $start = ($opt->{start} - $width < $NUM_OF_CHARS_IN_HEADER) ? $opt->{start} : $opt->{start} - $width;
    my $end = ($opt->{start} - $width < $NUM_OF_CHARS_IN_HEADER) ? $opt->{end} + 2 * $width : $opt->{end} + $width;

    my $flag = 1;
    my $annotationFlag = 0;
    my $pos = 0;
    my @linebuf;
    my @sentences = ();
    my $sid = -1;
    foreach my $line (split (/\n/, $content)) {

	$flag = 0 if ($line =~ /<InLinks>/);
	$flag = 1 if ($line =~ /<\/InLinks>/);
	$flag = 0 if ($line =~ /<OutLinks>/);
	$flag = 1 if ($line =~ /<\/OutLinks>/);

	next unless ($flag);

	$sid = $1 if ($line =~ /<S.+?Id="(\d+)">/);

	if ($line =~ /<Annotation/) {
	    $annotationFlag = 1;
	    next;
	}

	if ($line =~ /<\/Annotation>/) {
	    my $showFlag = 0;
	    my $number_of_included_queries = 0;
	    my %included_query_types = ();
	    foreach my $ln (@linebuf) {
		if ($ln =~ /^!! /) {
		} elsif ($ln =~ /^! /) {
		} elsif ($ln =~ /^\+ /) {
		} elsif ($ln =~ /^\* /) {
		} elsif ($ln =~ /^EOS$/) {
		} elsif ($ln =~ /^S\-ID:\d+$/) {
		} else {
		    $pos++;
		    if (exists $opt->{pos2qid}{$pos}) {
			$number_of_included_queries++;
			$included_query_types{$opt->{pos2qid}{$pos}}++;
		    }
		    $showFlag = 1 if ($start <= $pos && $pos <= $end && !$showFlag);
		}
	    }
	    my $result = join ("\n", @linebuf);

	    @linebuf = ();
	    $annotationFlag = 0;
	    $pos++;

	    # クエリ中の語が出現する範囲を超えた
	    last if (!$showFlag && $pos > $end);

	    if ($showFlag) {
		my $sentence = {
		    rawstring => '',
		    score => 0,
		    smoothed_score => 0,
		    words => {},
		    dpnds => {},
		    surfs => [],
		    reps => [],
		    sid => $sid,
		    number_of_included_queries => $number_of_included_queries,
		    number_of_included_query_types => scalar (keys %included_query_types),
		    num_of_whitespaces => 0
		};

 		$sentence->{result} = $result if ($opt->{keep_result});

 		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result, $opt);

 		my $num_of_whitespace_cdot_comma = 0;
		foreach my $w (@{$word_list}) {
		    my $surf = $w->{surf};
		    my $reps = $w->{reps};
		    $num_of_whitespace_cdot_comma++ if ($surf =~ /　|・|，|、|＞|−|｜|／/);

		    $sentence->{rawstring} .= $surf;
		    push(@{$sentence->{surfs}}, $surf);
		    push(@{$sentence->{reps}}, $w->{reps});
		}

		my $length = scalar(@{$sentence->{surfs}});
		$length = 1 if ($length < 1);
		my $score = $sentence->{number_of_included_query_types} * $sentence->{number_of_included_queries} * (log($length) + 1);
		$sentence->{score} = $score;
		$sentence->{smoothed_score} = $score;
		$sentence->{length} = $length;
		$sentence->{num_of_whitespaces} = $num_of_whitespace_cdot_comma;

		push(@sentences, $sentence);
	    }
	} else {
	    push (@linebuf, $line) if ($annotationFlag);
	}
    }

    if ($opt->{uniq}) {
	return &uniqSentences(\@sentences);
    } else {
	return \@sentences;
    }
}


sub isMatch {
    my ($listQ, $listS) = @_;

#    use Data::Dumper;
#    print Dumper($listS) . "\n";
#    print Dumper($listQ) . "\n";


    my $end = -1;
    my $matchQ = 0;
    for (my $i = 0; $i < scalar(@$listS); $i++) {
	for (my $j = 0; $j < scalar(@$listQ); $j++) {
	    # クエリレベルで代表表記がマッチしたか
	    $matchQ = 0;
	    # 単語レベルで代表表記がマッチしたか
	    my $matchW = 0;
	    foreach my $rep (keys %{$listS->[$i + $j]}) {
		# ワイルドカード(*)または同じ表現であれば
		if ($listQ->[$j] eq '*' || exists $listQ->[$j]{$rep}) {
		    $end = $i + $j;
		    $matchW = 1;
		    last;
		}
	    }

	    # マッチしなければ（文の方の）次の単語へ
	    unless ($matchW) {
		$end = -1;
		last;
	    }
	    $matchQ = 1;
	}

	if ($matchQ) {
	    return (1, $i, $end + 1);
	}
    }

    return (0, -1, -1);
}


sub isMatch2 {
    my ($listQ, $listS) = @_;

    use Data::Dumper;
#     print Dumper($listS) . "\n";
#     print Dumper($listQ) . "\n";

    my $start = -1;
    my $end = -1;

    foreach my $q_dpnd_repnames (@$listQ) {

	my $notFound = 0;
      OUT_OF_FOREACH:
	foreach my $s_dpnd_repnames (@$listS) {
	    $notFound = 0;
	    foreach my $s_dpnd_repname (keys %$s_dpnd_repnames) {
		if (exists $q_dpnd_repnames->{$s_dpnd_repname}) {

		    # 一文中に同一の係り受け関係が複数個含まれていないことを仮定
		    if ($start < 0) {
			$start = $s_dpnd_repnames->{$s_dpnd_repname}->{kakarimoto};
		    } else {
			$start = $s_dpnd_repnames->{$s_dpnd_repname}->{kakarimoto} if ($start > $s_dpnd_repnames->{$s_dpnd_repname}->{kakarimoto});
		    }

		    if ($end < 0) {
			$end = $s_dpnd_repnames->{$s_dpnd_repname}->{kakarisaki};
		    } else {
			$end = $s_dpnd_repnames->{$s_dpnd_repname}->{kakarisaki} if ($end < $s_dpnd_repnames->{$s_dpnd_repname}->{kakarisaki});
		    }

		    last OUT_OF_FOREACH;
		}
	    }
	    $notFound = 1;
	}

	# 含まれていない係り受けがあった
	if ($notFound) {
	    return (0, -1, -1);
	}
    }
    return (0, -1, -1) if ($start < 0 || $end < 0);

    # クエリ中の全係り受けが文中に含まれていた
    return (1, $start, $end + 1);
}


sub extract_sentences_from_content_for_kwic {
    my ($query, $content, $opt) = @_;

    my $sfdat = new StandardFormatData(\$content, $opt);

    my @sbuf;
    my $title = $sfdat->getTitle();
    my $queryString = $query->[$opt->{kwic_keyword_index}]{rawstring}; # kwic_keyword_index番目のqueryをkeywordとして用いる  (定義されていない場合は0番目、つまり初期クエリになる)

    my ($repnameList_q, $surfList_q, $repnameDpndList_q, $surfDpndList_q) = &makeMidasiAndRepnamesList($query->[$opt->{kwic_keyword_index}]{knp_result}->all(), $opt);
    $opt->{use_of_huzokugo_for_kwic} = 1;

    my $sentences = $sfdat->getSentences();
    for (my $i = 0; $i < scalar(@$sentences); $i++) {
	my $s = $sentences->[$i];
	my ($repnameList_s, $surfList_s, $repnameDpndList_s, $surfDpndList_s) = &makeMidasiAndRepnamesList($s->{annotation}, $opt);
	my ($flag, $from, $end) = ($opt->{use_of_repname_for_kwic}) ? &isMatch($repnameList_q, $repnameList_s) : &isMatch($surfList_q, $surfList_s);

	# 単語レベルでダメなら係り受けでチェックする
	if (!$flag && $opt->{use_of_dpnd_for_kwic}) {
	    ($flag, $from, $end) = ($opt->{use_of_repname_for_kwic}) ? &isMatch2($repnameDpndList_q, $repnameDpndList_s) : &isMatch2($surfDpndList_q, $surfDpndList_s);
	    if ($flag && $opt->{debug}) {
		print Dumper($repnameDpndList_q) . "\n";
		print "-----\n";
		print Dumper($repnameDpndList_s) . "\n";
		print "=====\n";
	    }
	}

	if ($flag) {
	    my $keyword;
	    my $contextL;
	    my $contextR;
	    for (my $j = 0; $j < scalar(@$surfList_s); $j++) {
		my $surf = (keys %{$surfList_s->[$j]})[0];
		# 活用形の情報を削除
		$surf =~ s/:.+$//;

		if ($j < $from) {
		    $contextL .= $surf;
		}
		elsif ($j > $end - 1) {
		    $contextR .= $surf;
		}
		else {
		    $keyword .=  $surf;
		}
	    }

	    # 左右のコンテキストを指定された幅に縮める

	    my @contextsR;
	    my $lengthR = length($contextR);
	    if ($lengthR > $opt->{kwic_window_size}) {
		push(@contextsR, substr($contextR, 0, $opt->{kwic_window_size}));
	    } else {
		push(@contextsR, $contextR);

		# $opt->{kwic_window_size} に満たない場合は、後続の文を取得する
		my $j = $i + 1;
		while ($j < scalar(@$sentences)) {
		    my $afterS = $sentences->[$j++]->{rawstring};
		    my $length = length($afterS);
		    if ($length + $lengthR > $opt->{kwic_window_size}) {
			my $diff = $opt->{kwic_window_size} - $lengthR;
			push(@contextsR, substr($afterS, 0, $diff));
			last;
		    } else {
			$lengthR += $length;
			push(@contextsR, $afterS);
		    }
		}
	    }

	    my @contextsL;
	    my $lengthL = length($contextL);
	    if ($lengthL > $opt->{kwic_window_size}) {
		my $offset = length($contextL) - $opt->{kwic_window_size};
		$offset = 0 if ($offset < 0);
		push(@contextsL, substr($contextL, $offset, $opt->{kwic_window_size}));
	    } else {
		push(@contextsL, $contextL);

		# $opt->{kwic_window_size} に満たない場合は、前方の文を取得する
		my $j = $i - 1;
		while ($j > -1) {
		    my $beforeS = $sentences->[$j]->{rawstring};
		    $j--;

		    my $length = length($beforeS);
		    if ($length + $lengthL > $opt->{kwic_window_size}) {
			my $diff = $opt->{kwic_window_size} - $lengthL;
			my $offset = $length - $diff;
			unshift(@contextsL, substr($beforeS, $offset, $diff));
			last;
		    } else {
			$lengthL += $length;
			unshift(@contextsL, $beforeS);
		    }
		}
	    }

	    # ソート用に逆右コンテキストを取得する
	    my $InvertedContextL = reverse(join("", @contextsL));
	    push(@sbuf, {title => $title->{rawstring},
			 rawstring => $s->{rawstring},
			 contextR => join('', @contextsR),
			 contextL => join('', @contextsL),
			 contextsR => \@contextsR,
			 contextsL => \@contextsL,
			 keyword => $keyword,
			 InvertedContextL => $InvertedContextL
		 });
	}
    }

    return \@sbuf;
}

# 見出しと代表表記の列を作成する
sub makeMidasiAndRepnamesList {
    my ($knpresult, $opt) = @_;

    # SYNGRAPHの情報を除く
    my $buf = undef;
    foreach my $line (split(/\n/, $knpresult)) {
	next if ($line =~ /^!/);
	$buf .= ($line . "\n");
    }
    $knpresult = $buf if (defined $buf);

    my @midasiList;
    my @midasiDpndList;
    my @repnameList;
    my @repnameDpndList;
    my $knpresultObj = new KNP::Result($knpresult);
    if (defined $knpresultObj) {
	# 各単語の出現位置を素性としてに付ける
	my $p = 0;
	foreach my $m ($knpresultObj->mrph) {
	    my @f = ();
	    push(@f, sprintf("出現位置:%d", $p++));
	    $m->push_feature(@f);
	}


	foreach my $self ($knpresultObj->tag) {
	    my ($midasiL_self, $repnameL_self, $posL_self) = &getMidasiAndRepnames($self, $opt);
	    push(@midasiList, @$midasiL_self);
	    push(@repnameList, @$repnameL_self);

	    my $kakarisaki = $self->parent();
	    next unless (defined $kakarisaki);

	    my ($midasiL_saki, $repnameL_saki, $posL_saki) = &getMidasiAndRepnames($kakarisaki, $opt);

	    # 出現形について係り受けを生成
	    # 基本句には、先頭にのみ内容語が現れると仮定
	    foreach my $m_self (keys %{$midasiL_self->[0]}) {
		my %midasiDpnds;
		foreach my $m_saki (keys %{$midasiL_saki->[0]}) {
		    my $dpnd = sprintf("%s->%s", $m_self, $m_saki);
		    $midasiDpnds{$dpnd}->{kakarimoto} = $posL_self->[0];
		    $midasiDpnds{$dpnd}->{kakarisaki} = $posL_saki->[0];

		}
		push(@midasiDpndList, \%midasiDpnds);
	    }

	    # 代表表記について係り受けを生成
	    # 基本句には、先頭にのみ内容語が現れると仮定
	    foreach my $r_self (keys %{$repnameL_self->[0]}) {
		my %repnameDpnds;
		foreach my $r_saki (keys %{$repnameL_saki->[0]}) {
		    my $dpnd = sprintf("%s->%s", $r_self, $r_saki);
		    $repnameDpnds{$dpnd}->{kakarimoto} = $posL_self->[0];
		    $repnameDpnds{$dpnd}->{kakarisaki} = $posL_saki->[0];

		}
		push(@repnameDpndList, \%repnameDpnds);
	    }
	}
    }

    return (\@repnameList, \@midasiList, \@repnameDpndList, \@midasiDpndList);
}


sub getMidasiAndRepnames {
    my ($kihonku, $opt) = @_;

    my @midasiL;
    my @repnameL;
    my @posL;
    my $negation = ($kihonku->fstring =~ /<否定表現>/) ? 1 : 0;
    foreach my $m ($kihonku->mrph) {
	my $midasi = &toUpperCase_utf8($m->midasi());
	my ($pos) = ($m->fstring() =~ /出現位置:(\d+)/);

	my %repnames = ();
	foreach my $repname (split(/\?/, $m->repnames())) {
	    $repname =~ s/\/.+$// if ($opt->{ignore_yomi});

	    $repnames{&toUpperCase_utf8($repname)} = 1;
	}

	if ($opt->{use_of_katuyou_for_kwic}) {
	    if ($m->hinsi() eq '動詞') {
		my $katuyou = $m->katuyou1() . ":" . $m->katuyou2();

		$midasi .= ":$katuyou";

		my %repnames_w_katuyou = ();
		foreach my $k (keys %repnames) {
		    $repnames_w_katuyou{$k . ":$katuyou"} = $repnames{$k};
		}
		%repnames = %repnames_w_katuyou;
	    }
	}


	if ($opt->{use_of_negation_for_kwic} && $negation) {
	    $midasi .= ":否定";

	    my %repnames_w_negation = ();
	    foreach my $k (keys %repnames) {
		$repnames_w_negation{$k . ":否定"} = $repnames{$k};
	    }
	    %repnames = %repnames_w_negation;
	}


	push(@posL, $pos);
	if (!$opt->{use_of_huzokugo_for_kwic} && $m->fstring() !~ /<内容語>/) {
	    push(@midasiL, '*');
	    push(@repnameL, '*');
	} else {
	    push(@midasiL, {$midasi => 1});
	    push(@repnameL, \%repnames);
	}
    }

    return (\@midasiL, \@repnameL, \@posL);
}

sub uniqSentences {
    my ($sentences) = @_;

    my %sbuf = ();
    my @sents = ();
    # スコアの高い順に処理（同点の場合は、sidの若い順）
    foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score} || $a->{sid} <=> $b->{sid}} @{$sentences}) {
	next if (exists($sbuf{$sentence->{rawstring}}));
	$sbuf{$sentence->{rawstring}} = 1;

	push (@sents, $sentence);
    }

    # sid順にソート
    @sents = sort {$a->{sid} <=> $b->{sid}} @sents;

    return \@sents;
}

sub extract_sentences_from_content {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $indexer = new Indexer({ignore_yomi => $opt->{ignore_yomi}});
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $paraid = 0;
    my $in_title = 0;
    my $in_link_tag = 0;
    my $in_meta_tag = 0;
    my $count = 0;
    my $th = -1;
    my $paragraph_first_sentence = 0;
    foreach my $line (split(/\n/, $content)) {
	$line .= "\n";
	if ($opt->{discard_title}) {
	    # タイトルはスニッペッツの対象としない
	    if ($line =~ /<Title [^>]+>/) {
		$in_title = 1;
	    } elsif ($line =~ /<\/Title>/ || $line =~ /<\/Header>/) {
		$in_title = 0;
	    }
	}
	next if ($in_title > 0);
	next if ($line =~ /^!/ && !$opt->{syngraph});

	$in_link_tag = 1 if ($line =~ /<InLinks>/);
	$in_link_tag = 0 if ($line =~ /<\/InLinks>/);
	$in_link_tag = 1 if ($line =~ /<OutLinks>/);
	$in_link_tag = 0 if ($line =~ /<\/OutLinks>/);

	$in_meta_tag = 1 if ($line =~ /<Description.*?>/);
	$in_meta_tag = 0 if ($line =~ /<\/Description>/);
	$in_meta_tag = 1 if ($line =~ /<Keywords.*?>/);
	$in_meta_tag = 0 if ($line =~ /<\/Keywords>/);
	$in_meta_tag = 1 if ($line =~ /<Abstract>/);
	$in_meta_tag = 0 if ($line =~ /<\/Abstract>/);

	next if ($in_link_tag || $in_meta_tag);

	$annotation .= $line;

	$sid = $1 if ($line =~ m!<S .+ Id="(\d+)"!);
	$sid = 0 if ($line =~ m!<Title !);

	$paraid = $1 if ($line =~ m!<S Paragraph="(\d+)"!);
	$paraid = 0 if ($line =~ m!<Title !);

	# 段落の先頭文かどうか
	if ($opt->{get_paragraph_first_sentence}) {
	    if ($line =~ m!<S !) {
		if ($line =~ m!ParagraphFirstSentence="1"!) {
		    $paragraph_first_sentence = 1;
		}
		else {
		    $paragraph_first_sentence = 0;
		}
	    }
	}

	if ($line =~ m!</Annotation>!) {
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;

		my $indice;
		my $resultObj;
		if ($opt->{syngraph}) {
		    $indice = $indexer->makeIndexfromSynGraph($result, undef, $opt);
		} else {
		    $resultObj = new KNP::Result($result);
		    $indice = $indexer->makeIndexFromKNPResultObject($resultObj, $opt);
		}

		my ($num_of_queries, $num_of_types, $including_all_indices) = &calculate_score($query, $indice, $opt);

		my $sentence = {
		    rawstring => undef,
		    score => 0,
		    smoothed_score => 0,
		    words => {},
		    dpnds => {},
		    surfs => [],
		    reps => [],
		    sid => $sid,
		    paraid => $paraid,
		    number_of_included_queries => $num_of_queries,
		    number_of_included_query_types => $num_of_types,
		    including_all_indices => $including_all_indices
		};

		$sentence->{resultObj} = $resultObj if ($opt->{keepResultObj});
		$sentence->{result} = $result if ($opt->{keep_result});
		$sentence->{paragraph_first_sentence} = $paragraph_first_sentence if ($opt->{get_paragraph_first_sentence});

		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result, $opt);

		my $num_of_whitespace_cdot_comma = 0;
		foreach my $w (@{$word_list}) {
		    my $surf = $w->{surf};
		    my $reps = $w->{reps};
		    $num_of_whitespace_cdot_comma++ if ($surf =~ /　|・|，|、|＞|−|｜|／/);

		    $sentence->{rawstring} .= $surf;
		    push(@{$sentence->{surfs}}, $surf);
		    push(@{$sentence->{reps}}, $w->{reps});
		}

		my $length = scalar(@{$sentence->{surfs}});
		$length = 1 if ($length < 1);
		my $score = $sentence->{number_of_included_query_types} * $sentence->{number_of_included_queries} * (log($length) + 1);
		$th = $count + $opt->{window_size} if ($score > 0 && $th < 0);
		$sentence->{score} = $score;
		$sentence->{smoothed_score} = $score;
		$sentence->{length} = $length;
		$sentence->{num_of_whitespaces} = $num_of_whitespace_cdot_comma;
		push(@sentences, $sentence);

		last if ($opt->{lightweight} && $count > $th && $th > 0);
		$count++;
#		print encode('euc-jp', $sentence->{rawstring}) . " (" . $num_of_whitespace_cdot_comma . ") is SKIPPED.\n";
	    }
	    $annotation = '';
	}
    }

    my $window_size = $opt->{window_size};
    my $size = scalar(@sentences);
    for (my $i = 0; $i < scalar(@sentences); $i++) {
	my $s = $sentences[$i];
	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i - $j - 1;
	    last if ($k < 0 || $s->{paraid} != $sentences[$k]->{paraid});
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}

	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i + $j + 1;
	    last if ($k > $size - 1 || $s->{paraid} != $sentences[$k]->{paraid});
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}
    }

    if ($opt->{uniq}) {
	return &uniqSentences(\@sentences);
    } else {
	return \@sentences;
    }
}

sub extract_sentences_from_metadata {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $tagname = (defined $opt->{tagname}) ? $opt->{tagname} : 'Abstract';
    my $indexer = new Indexer({ignore_yomi => $opt->{ignore_yomi}});
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $paraid = 0;
    my $in_title = 0;
    my $in_abstract_tag = 0;
    my $count = 0;
    my $th = -1;
    my $paragraph_first_sentence = 0;
    foreach my $line (split(/\n/, $content)) {
	$line .= "\n";
	if ($opt->{discard_title}) {
	    # タイトルはスニッペッツの対象としない
	    if ($line =~ /<Title [^>]+>/) {
		$in_title = 1;
	    } elsif ($line =~ /<\/Title>/ || $line =~ /<\/Header>/) {
		$in_title = 0;
	    }
	}
	next if ($in_title > 0);
	next if ($line =~ /^!/ && !$opt->{syngraph});
	last if ($line =~ !(</Header>|<Header/>)!);

	$in_abstract_tag = 1 if ($line =~ /<$tagname.*?>/);
	$in_abstract_tag = 0 if ($line =~ /<\/$tagname>/);

	next unless ($in_abstract_tag);

	$annotation .= $line;

	$sid = $1 if ($line =~ m!<S .+ Id="(\d+)"!);
	$sid = 0 if ($line =~ m!<Title !);

	$paraid = $1 if ($line =~ m!<S Paragraph="(\d+)"!);
	$paraid = 0 if ($line =~ m!<Title !);

	# 段落の先頭文かどうか
	if ($opt->{get_paragraph_first_sentence}) {
	    if ($line =~ m!<S !) {
		if ($line =~ m!ParagraphFirstSentence="1"!) {
		    $paragraph_first_sentence = 1;
		}
		else {
		    $paragraph_first_sentence = 0;
		}
	    }
	}

	if ($line =~ m!</Annotation>!) {
	    my ($rawstring) = ($annotation =~ m!<RawString>([^<]+?)</RawString>!);
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;

		my ($num_of_queries, $num_of_types, $including_all_indices);
		my $sentence = {
		    rawstring => $rawstring,
		    score => 0,
		    smoothed_score => 0,
		    words => {},
		    dpnds => {},
		    surfs => [],
		    reps => [],
		    sid => $sid,
		    paraid => $paraid,
		    number_of_included_queries => $num_of_queries,
		    number_of_included_query_types => $num_of_types,
		    including_all_indices => $including_all_indices
		};

		$sentence->{resultObj} = new KNP::Result($result) if ($opt->{keepResultObj});
		$sentence->{result} = $result if ($opt->{keep_result});
		$sentence->{paragraph_first_sentence} = $paragraph_first_sentence if ($opt->{get_paragraph_first_sentence});

		if (!$opt->{keyword_server_mode}) {
		    my $word_list = ($opt->{syngraph}) ? &make_word_list_syngraph($result) : &make_word_list($result, $opt);

		    my $num_of_whitespace_cdot_comma = 0;
		    foreach my $w (@{$word_list}) {
			my $surf = $w->{surf};
			my $reps = $w->{reps};
			$num_of_whitespace_cdot_comma++ if ($surf =~ /　|・|，|、|＞|−|｜|／/);

			push(@{$sentence->{surfs}}, $surf);
			push(@{$sentence->{reps}}, $w->{reps});
		    }

		    my $length = scalar(@{$sentence->{surfs}});
		    $length = 1 if ($length < 1);
		    my $score = $sentence->{number_of_included_query_types} * $sentence->{number_of_included_queries} * (log($length) + 1);
		    $th = $count + $opt->{window_size} if ($score > 0 && $th < 0);
		    $sentence->{score} = $score;
		    $sentence->{smoothed_score} = $score;
		    $sentence->{length} = $length;
		    $sentence->{num_of_whitespaces} = $num_of_whitespace_cdot_comma;
		}

		push(@sentences, $sentence);
		last if ($opt->{lightweight} && $count > $th && $th > 0);
		$count++;
	    }
	    $annotation = '';
	}
    }

    if ($opt->{uniq}) {
	return &uniqSentences(\@sentences);
    } else {
	return \@sentences;
    }
}


sub extract_sentences_from_content_old {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $indexer = new Indexer({ignore_yomi => $opt->{ignore_yomi}});
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $in_title = 0;
    foreach my $line (split(/\n/, $content)) {
	$line .= "\n";
	if ($opt->{discard_title}) {
	    # タイトルはスニッペッツの対象としない
	    if ($line =~ /<Title [^>]+>/) {
		$in_title = 1;
	    } elsif ($line =~ /<\/Title>/ || $line =~ /<\/Header>/) {
		$in_title = 0;
	    }
	}
	next if ($in_title > 0);
	next if ($line =~ /^!/ && !$opt->{syngraph});

	$annotation .= $line;

	$sid = $1 if ($line =~ m!<S .+ Id="(\d+)"!);
	$sid = 0 if ($line =~ m!<Title !);

	if ($line =~ m!</Annotation>!) {
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;
		my $indice = ($opt->{syngraph}) ? $indexer->makeIndexfromSynGraph($result, undef, $opt) : $indexer->makeIndexFromKNPResult($result, $opt);
		my ($num_of_queries, $num_of_types, $including_all_indices) = &calculate_score($query, $indice, $opt);

		my $sentence = {
		    rawstring => undef,
		    score => 0,
		    smoothed_score => 0,
		    words => {},
		    dpnds => {},
		    surfs => [],
		    reps => [],
		    sid => $sid,
		    number_of_included_queries => $num_of_queries,
		    number_of_included_query_types => $num_of_types,
		    including_all_indices => $including_all_indices
		};

		$sentence->{result} = $result if ($opt->{keep_result});
		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result, $opt);

		my $num_of_whitespace_cdot_comma = 0;
		foreach my $w (@{$word_list}) {
		    my $surf = $w->{surf};
		    my $reps = $w->{reps};
		    $num_of_whitespace_cdot_comma++ if ($surf =~ /　|・|，|、|＞|−|｜|／/);

		    $sentence->{rawstring} .= $surf;
		    push(@{$sentence->{surfs}}, $surf);
		    push(@{$sentence->{reps}}, $w->{reps});
		}

		my $length = scalar(@{$sentence->{surfs}});
		$length = 1 if ($length < 1);
		my $score = $sentence->{number_of_included_query_types} * $sentence->{number_of_included_queries} * log($length);
		$sentence->{score} = $score;
		$sentence->{smoothed_score} = $score;
		$sentence->{length} = $length;
		$sentence->{num_of_whitespaces} = $num_of_whitespace_cdot_comma;

		push(@sentences, $sentence);
#		print encode('euc-jp', $sentence->{rawstring}) . " (" . $num_of_whitespace_cdot_comma . ") is SKIPPED.\n";
	    }
	    $annotation = '';
	}
    }

    my $window_size = $opt->{window_size};
    my $size = scalar(@sentences);
    for (my $i = 0; $i < scalar(@sentences); $i++) {
	my $s = $sentences[$i];
	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i - $j - 1;
	    last if ($k < 0);
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}

	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i + $j + 1;
	    last if ($k > $size - 1);
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}
    }

    return \@sentences;
}

sub calculate_score {
    my ($query, $indice, $opt) = @_;

    my $num_of_queries = 0;
    my %matched_queries = ();
    my %buf;
    foreach my $idx (@$indice) {
	$buf{$idx->{midasi}}++;
    }

    if ($opt->{debug}) {
	print "index terms in a sentence\n";
	print Dumper (\%buf) . "\n";
	print "-----\n";
    }

    my $including_all_indices = 1;
    for (my $q = 0; $q < scalar(@{$query}); $q++) {
	my $qk = $query->[$q];
	foreach my $reps (@{$qk->{words}}) {
	    my $flag = 0;
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		$k =~ s/(a|v)$// unless ($opt->{string_mode});
		print $k . " is exists? -> " if ($opt->{debug});
		if (exists($buf{$k})) {
		    print "true.\n" if ($opt->{debug});
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		    $flag = 1;
		} else {
		    print "false.\n" if ($opt->{debug});
		}
	    }

	    $including_all_indices = 0 unless ($flag);
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    my $flag = 0;
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		$k =~ s/(a|v)//g unless ($opt->{string_mode});
		print $k . " is exists? -> " if ($opt->{debug});
		if (exists($buf{$k})) {
		    print "true.\n" if ($opt->{debug});
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		    $flag = 1;
		} else {
		    print "false.\n" if ($opt->{debug});
		}
	    }

	    $including_all_indices = 0 unless ($flag);
	}
    }
    print "=====\n" if ($opt->{debug});
    return ($num_of_queries, scalar(keys %matched_queries), $including_all_indices);
}

sub make_word_list {
    my ($sent, $opt) = @_;

    my @words;
    foreach my $line (split(/\n/,$sent)){
	next if ($line =~ /^\* \-?\d/);
	next if ($line =~ /^!/);
	next if ($line =~ /^S\-ID/);

	unless ($line =~ /^\+ (\-?\d+)([a-zA-Z])/){
	    next if ($line =~ /^(\<|\@|EOS)/);
	    next if ($line =~ /^\# /);

	    my @m = split(/\s+/, $line);

	    my $surf = $m[0];
	    my $midashi = "$m[2]/$m[1]";
	    my %reps = ();
	    ## 代表表記の取得
	    if ($line =~ /\<代表表記:([^>]+)\>/) {
		$midashi = $1;
	    }
	    $midashi =~ s/\/.+// if ($opt->{ignore_yomi});

	    $reps{&toUpperCase_utf8($midashi)} = 1;

	    ## 代表表記に曖昧性がある場合は全部保持する
	    ## ただし表記・読みが同一の代表表記は区別しない
	    ## ex) 日本 にっぽん 日本 名詞 6 地名 4 * 0 * 0 "代表表記:日本/にほん" <代表表記:日本/にほん><品曖><ALT-日本-にほん-日本-6-4-0-0-"代表表記:日本/にほん"> ...
	    my $lnbuf = $line;
	    while ($line =~ /\<ALT(.+?)\>/) {
		$line = "$'";
		my $alt_cont = $1;
		if ($alt_cont =~ /代表表記:(.+?)(?: |\")/) {
		    my $midashi = $1;
		    $midashi =~ s/\/.+// if ($opt->{ignore_yomi});
		    $reps{&toUpperCase_utf8($midashi)} = 1;
		} elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
		    my $midashi = ($opt->{ignore_yomi}) ? $3 : "$3/$2";
		    $reps{&toUpperCase_utf8($midashi)} = 1;
		}
	    }
	    $line = $lnbuf;

	    my @reps_array = sort keys %reps;
	    my $word = {
		surf => $surf,
		reps => \@reps_array,
		isContentWord => 0
	    };

	    push(@words, $word);

	    if ($line =~ /(<意味有>|<内容語>)/) {
		next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		$word->{isContentWord} = 1;
	    }
	} # end of else
    } # end of foreach my $line (split(/\n/,$sent))

    return \@words;
}

sub make_word_list_syngraph {
    my ($synresult) = @_;

    my @words;
    my $start = 0;
    my $bnstcnt = -1;
    my $wordcnt = 0;
    my %bnst2pos = ();
    foreach my $line (split(/\n/, $synresult)) {
	next if($line =~ /^!! /);
	next if($line =~ /^\* /);
	next if($line =~ /^# /);
	next if($line =~ /EOS/);

	if ($line =~ /^\+ /) {
	    $bnstcnt++;
	    next;
	}

	unless ($line =~ /^! /) {
	    my @m = split(/\s+/, $line);
	    my $surf = $m[0];
	    my $word = {
		surf => $surf,
		reps => [],
		isContentWord => 0
	    };
	    # 準内容語もハイライトの要素とする
	    # 準内容語の部分に、内容語を代入する
	    # 薬 の 効果 的な 飲み 方 → 薬 の 効果 効果 飲み 飲み
	    $word->{isContentWord} = 1 if ($line =~ /(<意味有>|<準?内容語>)/);

	    $words[$wordcnt] = $word;
	    push(@{$bnst2pos{$bnstcnt}}, $wordcnt);
	    $wordcnt++;
	} else {
	    my ($dumy, $bnstId, $syn_node_str) = split(/ /, $line);

	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $sid = $1;
		my $features = $3;
		$sid = $1 if ($sid =~ m!^([^/]+)/!);

		# 文法素性の削除
		$features =~ s/<可能>//;
		$features =~ s/<尊敬>//;
		$features =~ s/<受身>//;
		$features =~ s/<使役>//;
		$features =~ s/<上位語>//;

		# <下位語数:(数字)>を削除
		$features =~ s/<下位語数:\d+>//;

		foreach my $bid (split(/,/, $bnstId)) {
		    foreach my $pos (@{$bnst2pos{$bid}}) {
			next if ($words[$pos]->{isContentWord} < 1);
			push(@{$words[$pos]->{reps}}, "$sid$features");
		    }
		}
	    }
	} # end of else
    } # end of foreach my $line (split(/\n/,$sent))

    return \@words;
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

1;
