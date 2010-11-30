package Tsubaki::TermGroupCreater;

# $Id$

use strict;
use utf8;
use Indexer;
use Configure;
use CDB_File;
use Encode;
use Tsubaki::TermGroup;
use KNP::Result;

my $CONFIG = Configure::get_instance();

my $DFDBS_WORD = new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));

sub create {
    my ($result, $condition, $option) = @_;

    my @ids = ();
    my @kihonkus = $result->tag;
    my $rep2style = &_getRep2Style (\@kihonkus, \@ids, $option);
    my $synnode2midasi = &_getSynNode2Midasi (\@kihonkus, $option);
    my ($terms, $optionals) =
	(($condition->{is_phrasal_search} > 0) ?
	 &_create4phrase (\@kihonkus, \@ids, "", $option) :
	 &_create (0, \@kihonkus, \@ids, undef, "", $option));

    my $root = new Tsubaki::TermGroup (
	-1,
	-1,
	-1,
	undef,
	undef,
	undef,
	undef,
	$terms,
	{
	    isRoot         => 1,
	    optionals      => $optionals,
	    result         => $result,
	    condition      => $condition,
	    rep2style      => $rep2style,
	    synnode2midasi => $synnode2midasi
	});

    return $root;
}

# スニペット表示の際に利用するタームのスタイルシートを生成
sub _getRep2Style {
    my ($kihonkus, $ids, $option) = @_;

    my %rep2style = ();
    foreach my $i (0 .. scalar (@$kihonkus) - 1) {
	next if ($kihonkus->[$i]->fstring =~ /クエリ削除語/);

	push (@$ids, $i);
	my $j = $i % scalar(@{$CONFIG->{HIGHLIGHT_COLOR}});
	foreach my $synnodes ($kihonkus->[$i]->synnodes) {
	    foreach my $synnode ($synnodes->synnode) {
		next if ($synnode->synid =~ /s\d+/ && $option->{disable_synnode});
		$rep2style{&remove_yomi(lc($synnode->synid))} = sprintf ("background-color: %s; color: %s; margin:0.1em 0.25em;", $CONFIG->{HIGHLIGHT_COLOR}[$j], (($j > 4) ? 'white' : 'black'));
	    }
	}
    }

    return \%rep2style;
}

# synnodeからクエリ中に出現した見出しへのマップを作成
sub _getSynNode2Midasi {
    my ($kihonkus, $opt) = @_;

    my @midasi = ();
    my %synnode2midasi = ();
    foreach my $i (0 .. scalar(@$kihonkus) - 1) {
	my $surf;
	foreach my $m ($kihonkus->[$i]->mrph) {
	    next if ($m->fstring !~ /<内容語>/);
	    $surf .= $m->midasi;
	}
	$midasi[$i] = $surf;

	foreach my $synnodes ($kihonkus->[$i]->synnodes()) {
	    foreach my $synnode ($synnodes->synnode()) {
		# 読みの削除
		my $_midasi = sprintf ("%s%s", &remove_yomi($synnode->synid), $synnode->feature);

		# <反義語><否定>を利用するかどうか
		if ($_midasi =~ /<反義語>/ && $_midasi =~ /<否定>/) {
		    next unless ($opt->{option}{use_of_negation_and_antonym});
		}

		# 文法素性の削除
		$_midasi = &removeSyntacticFeatures($_midasi);
		foreach my $tid (split (/,/, $synnode->tagid)) {
		    $synnode2midasi{$_midasi} .= $midasi[$tid];
		}
	    }
	}
    }

    return \%synnode2midasi;
}

sub _create4phrase {
    my ($kihonkus, $tids, $space, $opt) = @_;

    my ($gid, $count, @terms, %optionals, %visitedKihonkus) = (0, 0, (), (), ());
    foreach my $tid (@$tids) {
	my $kihonku = $kihonkus->[$tid];
	foreach my $mrph ($kihonku->mrph) {
	    my $midasi = sprintf ("%s*", &remove_yomi($mrph->midasi));
	    my $gdf = $DFDBS_WORD->get($midasi);

	    # タームグループの作成
	    my @midasis = ();
	    push (@midasis, $midasi);
	    push (@terms, new Tsubaki::TermGroup (
		      $gid++,
		      $tid,
		      $gdf,
		      undef,
		      undef,
		      \@midasis,
		      undef,
		      undef,
		      $opt
		  ));
	}

	# 係り受けタームの追加
	&_pushbackDependencyTerms(\@terms, \%optionals, $kihonku, $gid, $count, $opt);
    }

    return (\@terms, \%optionals);
}

sub _create {
    my ($gid, $kihonkus, $tids, $parent, $space, $option) = @_;

    my ($count, @terms, %optionals, %visitedKihonkus) = (0, (), (), ());
    foreach my $tid (reverse @$tids) {
	my $kihonku = $kihonkus->[$tid];

	next if (exists $visitedKihonkus{$tid});
	next if ($kihonku->fstring =~ /クエリ削除語/);

	my $is_optional_node = (defined $kihonku && $kihonku->fstring =~ /クエリ不要語/) ? 1 : 0;
	my $broadest_synnodes = &_getBroadestSynNode ($parent, $kihonku, $tids);
	my @synnodes = $broadest_synnodes->synnode;

	# 既に見た基本句IDを登録
	my @tagids = $synnodes[0]->tagids;
	foreach my $_tid (@tagids) {
	    $visitedKihonkus{$_tid} = 1;
	}

	# SYNNODEがカバーしている要素を獲得
	my $group_id = sprintf ("%s-%s", $gid , $count++);
	my $children = &_getChildNodes (\%optionals, $group_id, $kihonkus, \@tagids, $broadest_synnodes, $space, $option);

	# タームグループの作成
	my $termGroups = &_createTermGroup ($group_id, $tid, \@synnodes, $kihonku, $children, { optional_flag => $is_optional_node, option => $option });

	foreach my $termGroup (@$termGroups) {
	    if ($is_optional_node) {
		$optionals{$termGroup->{text}} = $termGroup unless (defined ($optionals{$termGroup->{text}}));
	    } else {
		unshift (@terms, $termGroup);
	    }
	}

	# 係り受けタームの追加
	&_pushbackDependencyTerms (\@terms, \%optionals, $kihonku, $gid, $count, $option);
    }

    return (\@terms, \%optionals);
}

sub reduceSynNode {
    my ($basic_node, $synnodes, $opt) = @_;

    next unless (defined $synnodes);

    my $N = ($opt->{use_of_antonym_expansion}) ? int (0.5 * ($CONFIG->{MAX_NUMBER_OF_SYNNODES} + 1)) : $CONFIG->{MAX_NUMBER_OF_SYNNODES};

    # 各ノードのgdfを得る
    my $count = 0;
    my @newNodes = ();

    push (@newNodes, $basic_node) if (defined $basic_node);
    foreach my $node (sort {$DFDBS_WORD->get(&remove_yomi($b->synid)) <=> $DFDBS_WORD->get(&remove_yomi($a->synid)) } @$synnodes) {
	next if ($basic_node == $node);
	push (@newNodes, $node) if (defined $node);
	last if (++$count >= $N);
    }

    return \@newNodes;
}

sub _getDF {
    my ($basicNd, $synNds) = @_;

    if ($basicNd) {
	return $DFDBS_WORD->get(&remove_yomi($basicNd->synid), {exhaustive => 1});
    } else {
	return $DFDBS_WORD->get(&remove_yomi($synNds->[0]->synid), {exhaustive => 1}) if (defined $synNds);
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

sub getBasicNode {
    my ($synnodes) = @_;

    foreach my $synnode (@$synnodes) {
	if ($synnode->synid !~ /^s\d+/ && $synnode->feature eq '') {
	    return $synnode;
	}
    }
    return undef;
}

sub removeSyntacticFeatures {
    my ($midasi) = @_;

    $midasi =~ s/<可能>//;
    $midasi =~ s/<尊敬>//;
    $midasi =~ s/<受身>//;
    $midasi =~ s/<使役>//;

    return $midasi;
}

sub expandAntonymAndNegationTerms {
    my ($midasi, $opt) = @_;

    my @buf;
    push (@buf, $midasi);
    # 拡張するタームを最後のものに限定する必要あり
    if ($opt->{option}{antonym_and_negation_expansion}) {
	# 反義情報の削除
	$midasi =~ s/<反義語>//;

	# <否定>の付け変え
	if ($midasi =~ /<否定>/) {
	    $midasi =~ s/<否定>//;
	} else {
	    $midasi .= '<否定>';
	}
	push (@buf, $midasi);
    }

    return \@buf;
}

sub _createTermGroup {
    my ($gid, $tid, $synNds, $parent, $children, $opt) = @_;

    my $basicNd = &getBasicNode($synNds);
    $synNds = &reduceSynNode($basicNd, $synNds, $opt) if ($CONFIG->{MAX_NUMBER_OF_SYNNODES});
    my $gdf = &_getDF ($basicNd, $synNds);

    my @midasis = ();
    foreach my $synNd (@$synNds) {
	my $_midasi = sprintf ("%s%s", &remove_yomi($synNd->synid), $synNd->feature);

	# <反義語><否定>を利用するかどうか
	if ($_midasi =~ /<反義語>/ && $_midasi =~ /<否定>/) {
	    next unless ($opt->{option}{use_of_negation_and_antonym});
	}

	# SYNノードを利用しない場合
	next if ($_midasi =~ /s\d+/ && $opt->{option}{disable_synnode});

	# 文法素性の削除
	$_midasi = &removeSyntacticFeatures($_midasi);

	# 反義語を使ってタームを拡張する
	my $_midasis = &expandAntonymAndNegationTerms($_midasi, $opt);

	push (@midasis, @$_midasis);
    }

    # タームグループの作成
    if (scalar (@midasis) < 1) {
	return $children;
    } else {
	my $tg = new Tsubaki::TermGroup (
	    $gid,
	    $tid,
	    $gdf,
	    undef,
	    ((defined $basicNd) ? &remove_yomi($basicNd->synid) : ''),
	    \@midasis,
	    $parent,
	    $children,
	    $opt
	    );

	my @__buf = (); push (@__buf, $tg);
	return \@__buf;
    }
}

# もっとも大きいsynnodeを獲得
sub _getBroadestSynNode {
    my ($parent, $kihonku, $ids) = @_;

    my $broadest_synnodes;
    foreach my $synnodes ($kihonku->synnodes) {
	last if ($synnodes == $parent);

	# synnodeが交差する場合は、交差しなくなるまで子をだどる
	# 例) 水の中に潜る -> s22145:水中, s10424:中に潜る
	my $node = ($synnodes->synnode)[0];
	my $head = ($node->tagids)[0];
	next if ($ids->[0] > $head);

	$broadest_synnodes = $synnodes;
    }

    return $broadest_synnodes;
}

sub _getChildNodes {
    my ($optionals, $group_id, $kihonkus, $tagids, $broadest_synnodes, $space, $option) = @_;

    my $children = undef;
    if (scalar (@$tagids) > 1) {
	my $_optionals;
	($children, $_optionals) = &_create ($group_id, $kihonkus, $tagids, $broadest_synnodes, $space ."\t", $option);
	foreach my $k (keys %$_optionals) {
	    $optionals->{$k} = $_optionals->{$k} unless (exists ($optionals->{$k}));
	}
    }

    return $children;
}

sub _pushbackDependencyTerms {
    my ($terms, $optionals, $kihonku, $gid, $count, $option) = @_;

    # 係り受けを追加
    my $indexer = new Indexer({ignore_yomi => 1});
    if (defined $kihonku->parent && $kihonku->fstring !~ /<クエリ削除係り受け>/) {
	my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
	my $kakarimoto = $indexer->get_repnames2($kihonku);
	my $kakarisaki = $indexer->get_repnames2($kihonku->parent);
	my $is_optional_node = ($kihonku->fstring =~ /<クエリ必須係り受け>/) ? 0 : (($option->{force_dpnd}) ? 0 : 1);
	my @_terms;
	foreach my $moto (@$kakarimoto) {
	    foreach my $saki (@$kakarisaki) {
		my $midasi = sprintf ("%s->%s", $moto, $saki);
		my $gdf = $DFDBS_DPND->get($midasi, {exhaustive => 1});
		my $blockTypes = ($CONFIG->{USE_OF_BLOCK_TYPES}) ? $option->{blockTypes} : {"" => 1};

		foreach my $tag (keys %{$blockTypes}) {
		    my $term = new Tsubaki::Term ({
			tid => sprintf ("%s-%s", $gid, $count++),
			text => $midasi,
			term_type => (($is_optional_node) ? 'dpnd' : 'force_dpnd'),
			gdf => $gdf,
			blockType => (($tag eq '') ? undef : $tag),
			node_type => 'basic' });

		    if ($is_optional_node) {
			$optionals->{$term->get_id()} = $term unless (exists $optionals->{$term->get_id()});
		    } else {
			push (@_terms, $term);
		    }
		}
	    }
	}

	unless ($is_optional_node) {
	    my $termG = new Tsubaki::TermGroup();
	    if (scalar (@_terms) > 0) {
		$termG->{terms} = \@_terms;
		push (@$terms, $termG);
	    }
	}
    }
}


sub getPaintingJavaScriptCode {
    my ($result, $colorOffset, $opt) = @_;

    ###### 変数の初期化 #####

    my $REQUISITE = '<クエリ必須語>';
    my $OPTIONAL  = '<クエリ不要語>';
    my $IGNORE    = '<クエリ削除語>';
    my $REQUISITE_DPND = '<クエリ必須係り受け>';

    my $font_size = 12;
    my $offsetX = 10 + 24;
    my $offsetY = $font_size * (scalar($result->tag) + 3);
    my $arrow_size = 3;
    my $synbox_margin = $font_size;

    my @color = ();
    push(@color, '#ffa500;');
    push(@color, '#000080;');
    push(@color, '#779977;');
    push(@color, '#800000;');
    push(@color, '#997799;');
    push(@color, '#770000;');
    push(@color, '#007700;');
    push(@color, '#777700;');
    push(@color, '#007777;');
    push(@color, '#770077;');

    my @bgcolor = ();
    push(@bgcolor, '#ffff99;');
    push(@bgcolor, '#bbffff;');
    push(@bgcolor, '#bbffbb;');
    push(@bgcolor, '#ffbbbb;');
    push(@bgcolor, '#ffbbff;');
    push(@bgcolor, '#bb0000;');
    push(@bgcolor, '#00bb00;');
    push(@bgcolor, '#bbbb00;');
    push(@bgcolor, '#00bbbb;');
    push(@bgcolor, '#bb00bb;');

    my @stylecolor = ();
    push(@stylecolor, 'border: 2px solid #ffa500; background-color: #ffff99;');
    push(@stylecolor, 'border: 2px solid #000080; background-color: #bbffff;');
    push(@stylecolor, 'border: 2px solid #779977; background-color: #bbffbb;');
    push(@stylecolor, 'border: 2px solid #800000; background-color: #ffbbbb;');
    push(@stylecolor, 'border: 2px solid #997799; background-color: #ffbbff;');
    push(@stylecolor, 'border: 2px solid #770000; background-color: #bb0000; color: white;');
    push(@stylecolor, 'border: 2px solid #007700; background-color: #00bb00; color: white;');
    push(@stylecolor, 'border: 2px solid #777700; background-color: #bbbb00; color: white;');
    push(@stylecolor, 'border: 2px solid #007777; background-color: #00bbbb; color: white;');
    push(@stylecolor, 'border: 2px solid #770077; background-color: #bb00bb; color: white;');

    my $removedcolor = 'border: 2px solid #9f9f9f; background-color: #e0e0e0; color: black;';

    #########################


    my $jscode .= qq(jg.clear();\n);

    # 単語・同義表現グループを描画する
    my $max_num_of_synonyms = 0;
    my %gid2pos = ();
    my %gid2num = ();
    my @kihonkus = $result->tag;
    my $syngraph = Configure::getSynGraphObj();
    
    my %tid2syns = ();
    for (my $i = 0; $i < scalar(@kihonkus); $i++) {
	my $tag = $kihonkus[$i];

	my $gid = ($tag->synnodes)[0]->tagid;
	$gid2num{$gid} = $i;

	my ($synbuf, $max_num_of_words) = &_getExpressions($i, $tag, \%tid2syns, $syngraph, $opt);

	my $width = $font_size * (1.5 + $max_num_of_words);
	# 同義グループのX軸の中心座標を保持（係り受けの線を描画する際に利用する）
	$gid2pos{$gid}->{pos} = $offsetX + int(0.5 * $width);
	$gid2pos{$gid}->{num_child} = 0;
	$gid2pos{$gid}->{num_parent} = 1;

	# 下に必須・オプショナルのフラグを取得
	my $mark = ($tag->fstring() =~ /クエリ削除語/) ? 'Ｘ' : (($tag->fstring() =~ /クエリ不要語/) ?  '△' : '〇');
	my $colorIndex = ($i + $colorOffset) % scalar(@stylecolor);

	my $synbox;
	if ($tag->fstring() =~ /<クエリ削除語>/) {
	    $synbox .= sprintf(qq(<TABLE style=\\'font-size: $font_size; margin: 0px;text-align: center; $removedcolor\\' width=%dpx>), $width);
	} else {
	    $synbox .= sprintf(qq(<TABLE style=\\'font-size: $font_size; margin: 0px;text-align: center; $stylecolor[$colorIndex]\\' width=%dpx>), $width);
	}

	my $surf = ($tag->synnodes)[0]->midasi;
	if (scalar(keys %$synbuf) > 0) {
	    my $rate = 36;
	    my ($r, $g, $b) = ($bgcolor[$colorIndex] =~ /#(..)(..)(..);/);
	    $r = (hex($r) + $rate > 255) ? 'ff' : sprintf ("%x", hex($r) + $rate);
	    $g = (hex($g) + $rate > 255) ? 'ff' : sprintf ("%x", hex($g) + $rate);
	    $b = (hex($b) + $rate > 255) ? 'ff' : sprintf ("%x", hex($b) + $rate);
	    my $dilutedColor = sprintf("#%s%s%s", $r, $g, $b);

	    $synbox .= sprintf(qq(<TR><TD style=\\'border-bottom: 1px solid %s;\\'>%s</TD></TR>), $color[$colorIndex], $surf);
	    $synbox .= sprintf(qq(<TR><TD style=\\'background-color: %s;\\'>%s</TD></TR>), $dilutedColor, join("<BR>", sort keys %$synbuf));
	} else {
	    $synbox .= sprintf(qq(<TR><TD>%s</TD></TR>), $surf);
	}
	$synbox .= "</TABLE>";

	$max_num_of_synonyms = scalar(keys %$synbuf) if ($max_num_of_synonyms < scalar(keys %$synbuf));

	$jscode .= qq(jg.drawStringRect(\'$synbox\', $offsetX, $offsetY, $width, 'left');\n);
	$jscode .= qq(jg.drawStringRect(\'$mark\', $offsetX, $offsetY - 1.05 * $font_size, $font_size, 'left');\n);
	$offsetX += ($width + $synbox_margin);
    }
    $colorOffset += scalar(scalar($result->tag));

    # 解析結果を表示するウィンドウの幅、高さを求める
    my $width = $offsetX;
    my $height = $offsetY + int(($max_num_of_synonyms + 1) * 1.1 * $font_size); # +1 は●▲の分, *1.1 は行間



    for (my $i = 0; $i < scalar(@kihonkus); $i++) {
	my $kakarimoto = $kihonkus[$i];
	my $kakarisaki = $kakarimoto->parent;

	# 並列句の処理１
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 日本->政治, 日本->経済 の部分
	if ($kakarimoto->dpndtype ne 'P') {
	    $jscode .= &getDrawingDependencyCodeForParaType1($kakarimoto, $kakarisaki, $i, $offsetX, $offsetY, $arrow_size, $font_size, \%gid2num, \%gid2pos);
	}

	# 並列句の処理２
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 政治->正す, 経済->正す の部分
	my $buf = $kakarimoto;
	while ($buf->dpndtype eq 'P' && defined $kakarisaki->parent) {
	    $buf = $kakarisaki;
	    $kakarisaki = $kakarisaki->parent;
	}

 	next unless (defined $kakarisaki);

	# 追加された係り受けの描画
	if ($kakarimoto->fstring() !~ /<クエリ削除係り受け>/ &&
	    $kakarisaki->fstring() =~ /<クエリ不要語>/ &&
	    $kakarisaki->fstring() !~ /<クエリ削除語>/ &&
	    $kakarisaki->fstring() !~ /<固有表現を修飾>/) {
	    my $_kakarisaki = $kakarisaki->parent();

	    # 係り先の係り先への係り受けを描画
	    if (defined $_kakarisaki) {
		my $mark = ($_kakarisaki->fstring() =~ /クエリ削除語/) ?  'Ｘ' : '△';
		$jscode .= &getDrawingDependencyCode($i, $kakarimoto, $_kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, \%gid2num, \%gid2pos);
	    }
	}

	my $mark = ($kakarimoto->fstring() =~ /クエリ必須係り受け/) ?  '〇' : (($kakarimoto->fstring() =~ /クエリ削除係り受け/) ? 'Ｘ' : '△');
	$mark = 'Ｘ' if (defined $kakarisaki && $kakarisaki->fstring() =~ /<クエリ削除語>/);
	$jscode .= &getDrawingDependencyCode($i, $kakarimoto, $kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, \%gid2num, \%gid2pos);
    }


    $jscode .= qq(jg.setFont(\'ＭＳゴシック\', \'$font_size\', 0);\n);
    $jscode .= qq(jg.paint();\n);

    return ($width, $height, $colorOffset, $jscode);
}

sub getDrawingDependencyCodeForParaType1 {
    my ($kakarimoto, $kakarisaki, $i, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos) = @_;

    my $jscode;
    if (defined $kakarisaki && defined $kakarisaki->child) {
	foreach my $child ($kakarisaki->child) {
	    # 係り受け関係を追加する際、係り元のノード以前は無視する
	    # ex) 緑茶やピロリ菌
	    if ($child->dpndtype eq 'P' && $child->id > $kakarimoto->id) {
		my $mark = ($child->fstring() =~ /クエリ削除語/) ?  'Ｘ' : '△';
		$jscode .= &getDrawingDependencyCode($i, $kakarimoto, $child, $mark, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos);

		# 子の子についても処理する
		$jscode .= &getDrawingDependencyCodeForParaType1($kakarimoto, $child, $i, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos);
	    }
	}
    }
    return $jscode;
}

sub getDrawingDependencyCode {
    my ($i, $kakarimoto, $kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos) = @_;

    my $jscode = '';

    my $kakarimoto_gid = ($kakarimoto->synnodes)[0]->tagid;
    my $kakarisaki_gid = ($kakarisaki->synnodes)[0]->tagid;

    my $dist = abs($i - $gid2num->{$kakarisaki_gid});

    my $x1 = $gid2pos->{$kakarimoto_gid}->{pos} + (3 * $gid2pos->{$kakarimoto_gid}->{num_parent} * $arrow_size);
    my $x2 = $gid2pos->{$kakarisaki_gid}->{pos} - (3 * $gid2pos->{$kakarisaki_gid}->{num_child} * $arrow_size);
    $gid2pos->{$kakarimoto_gid}->{num_parent}++;
    $gid2pos->{$kakarisaki_gid}->{num_child}++;

    my $y = $offsetY - $font_size - (1.5 * $dist * $font_size);


    # 係り受けの線をひく

    if ($mark eq 'Ｘ') {
	$jscode .= qq(jg.setStroke(Stroke.DOTTED);\n);
    } else {
	$jscode .= qq(jg.setStroke(1);\n);
    }

    $jscode .= qq(jg.drawLine($x1, $offsetY, $x1, $y);\n);
    $jscode .= qq(jg.drawLine($x1 - 1, $offsetY, $x1 - 1, $y);\n);

    $jscode .= qq(jg.drawLine($x1, $y, $x2, $y);\n);
    $jscode .= qq(jg.drawLine($x1, $y - 1, $x2, $y - 1);\n);

    $jscode .= qq(jg.drawLine($x2, $y, $x2, $offsetY);\n);
    $jscode .= qq(jg.drawLine($x2 + 1, $y, $x2 + 1, $offsetY);\n);

    # 矢印
    $jscode .= qq(jg.fillPolygon(new Array($x2, $x2 + $arrow_size, $x2 - $arrow_size), new Array($offsetY, $offsetY - $arrow_size, $offsetY - $arrow_size));\n);


    # 線の上に必須・オプショナルのフラグを描画する
    $jscode .= qq(jg.drawStringRect(\'$mark\', $x1, $y - 1.05 * $font_size, $font_size, 'left');\n);

    return $jscode;
}


sub _getNormalizedString {
    my ($str) = @_;

    my ($yomi) = ($str =~ m!/(.+?)(?:v|a)?$!);
    $str =~ s/\[.+?\]//g;
    $str =~ s/(\/|:).+//;
    $str = lc($str);
    $str =~ s/人」/人/;

    return ($str, $yomi);
}

sub _pushbackBuf {
    my ($i, $tid2syns, $string, $yomi, $functional_word) = @_;

    foreach my $e (($string, $yomi)) {
	next unless ($e);

	$tid2syns->{$i}{$e} = 1;
	$tid2syns->{$i}{sprintf ("%s%s", $e, $functional_word)} = 1;
    }
}

sub _getPackedExpressions {
    my ($i, $synbuf, $tid2syns, $tids, $str, $functional_word, $syngraph) = @_;

    my %buf = ();
    my @synonymous_exps = split(/\|+/, decode('utf8', $syngraph->{syndb}{$str}));
    my $max_num_of_words = 0;
    if (scalar(@synonymous_exps) > 1) {
	foreach my $_string (@synonymous_exps) {
	    my ($string, $yomi) = &_getNormalizedString($_string);
	    &_pushbackBuf($i, $tid2syns, $string, undef, $functional_word);
	    $buf{$string} = 1;
	}

	foreach my $string (keys %buf) {
	    my $matched_exp = undef;
	    if (scalar(@$tids) > 1) {
		my $_string = $string;
		foreach my $tid (@$tids) {
		    my $isMatched = 0;
		    foreach my $_prev (sort {length($b) <=> length($a)} keys %{$tid2syns->{$tid}}) {
			if ($_string =~ /^$_prev/) {
			    $matched_exp .= $_prev;
			    $_string = "$'";
			    $isMatched = 1;
			    last;
			}
		    }

		    # 先行する語とマッチしなければ終了
		    last unless ($isMatched);
		}
	    }

	    unless ($matched_exp) {
		$synbuf->{$string} = 1;
	    } else {
		if ($string ne $matched_exp) {
		    $string =~ s/$matched_exp/（$matched_exp）/;
		    $synbuf->{$string} = 1;
		}
	    }
	    $max_num_of_words = length($string) if ($max_num_of_words < length($string));
	}
    }

    return $max_num_of_words;
}


# 同義グループに属す表現の取得と幅（文字数）の取得
sub _getExpressions {
    my ($i, $tag, $tid2syns, $syngraph, $opt) = @_;


    my $surf = ($tag->synnodes)[0]->midasi;
    my $surf_contentW = ($tag->mrph)[0]->midasi;
    my @repnames_contentW = ($tag->mrph)[0]->repnames;
    my $max_num_of_words = length($surf);
    my $functional_word = (($tag->mrph)[-1]->fstring !~ /<内容語>/) ? ($tag->mrph)[-1]->midasi : '';
    $functional_word =~ s!/.*$!!;

    my @basicNodes = ();
    my %synbuf;
    unless ($tag->fstring() =~ /<クエリ削除語>/) {
	foreach my $synnodes ($tag->synnodes) {
	    foreach my $node ($synnodes->synnode) {
		next if ($node->feature =~ /<上位語>/ || $node->feature =~ /<反義語>/ || $node->feature =~ /<否定>/);

		# 基本ノードの獲得
		my $str = $node->synid;
		if ($str !~ /s\d+/) {
		    my ($_str, $_yomi) = &_getNormalizedString($str);
		    push (@basicNodes, $_str);
		    push (@basicNodes, $_yomi) if ($_yomi);
		    &_pushbackBuf($i, $tid2syns, $_str, $_yomi, $functional_word);
		}


		# 同義グループに属す表現の取得
		unless ($opt->{disable_synnode}) {
		    my @tids = $synnodes->tagids;
		    my $max_num_of_w = &_getPackedExpressions($i, \%synbuf, $tid2syns, \@tids, $str, $functional_word, $syngraph);
		    $max_num_of_words = $max_num_of_w if ($max_num_of_words < $max_num_of_w);
		}
	    }
	}

	# 出現形、基本ノードと同じ表現は削除する
	delete ($synbuf{$surf});
	delete ($synbuf{$surf_contentW});
	foreach my $basicNode (@basicNodes) {
	    delete ($synbuf{$basicNode});
	}
	foreach my $rep (@repnames_contentW) {
	    foreach my $word_w_yomi (split (/\?/, $rep)) {
		my ($hyouki, $yomi) = split (/\//, $word_w_yomi);
		delete ($synbuf{$hyouki});
	    }
	}
    }

    return (\%synbuf, $max_num_of_words);
}

1;
