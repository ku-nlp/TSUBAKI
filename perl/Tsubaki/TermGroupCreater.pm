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


sub create {
    my ($result, $option) = @_;

    my @kihonkus = $result->tag;

    my @ids = ();
    foreach my $i (0 .. scalar (@kihonkus) - 1) {
	push (@ids, $i);
    }

    my ($terms, $optionals) = &_create (0, \@kihonkus, \@ids, undef, "", $option);

    my $root = new Tsubaki::TermGroup (
	-1,
	undef,
	undef,
	undef,
	$terms,
	undef,
	{
	    isRoot => 1,
	    optionals => $optionals,
	    result => $result
	});

    return $root;
}

sub _create {
    my ($gid, $kihonkus, $ids, $parent, $space, $option) = @_;

    my @terms;
    my %optionals = ();
    my $count = 0;
    my %visitedKihonkus = ();
    foreach my $k (reverse @$ids) {
	next if (exists $visitedKihonkus{$k});
	my $kihonku = $kihonkus->[$k];

	# もっとも大きいsynnodeを獲得
	my $widest_synnodes;
	foreach my $synnodes ($kihonku->synnodes) {
	    last if ($synnodes == $parent);

	    # synnodeが交差する場合は、交差しなくなるまで子をだどる
	    # 例) 水の中に潜る -> s22145:水中, s10424:中に潜る
	    my $rep = ($synnodes->synnode)[0];
	    my $head = ($rep->tagids)[0];
	    next if ($ids->[0] > $head);

	    $widest_synnodes = $synnodes;
	}
	my @synnodes = $widest_synnodes->synnode;

	my $rep = $synnodes[0];
	my @tagids = $rep->tagids;
	foreach my $tid (@tagids) {
	    $visitedKihonkus{$tid} = 1;
	}


	my $children = undef;
	my $group_id = sprintf ("%s-%s", $gid , $count++);
	if (scalar (@tagids) > 1) {
	    my $_optionals;
	    ($children, $_optionals) = &_create ($group_id, $kihonkus, \@tagids, $widest_synnodes, $space ."\t", $option);
	    foreach my $k (keys %$_optionals) {
		$optionals{$k} = $_optionals->{$k} unless (defined ($optionals{$k}));
	    }
	}

	my $optional_flag = (defined $kihonku && $kihonku->fstring =~ /クエリ不要語/) ? 1 : 0;
	my $term = new Tsubaki::TermGroup (
	    $group_id,
	    undef,
	    \@synnodes,
	    \@tagids,
	    $children,
	    $kihonku,
	    {
		optional_flag => $optional_flag,
		option => $option
	    });

	if ($optional_flag) {
	    $optionals{$term->{text}} = $term unless (defined ($optionals{$term->{text}}));
	} else {
	    unshift (@terms, $term);
	}

	# 係り受けを追加
	my $indexer = new Indexer({ignore_yomi => 1});
	if (defined $kihonku->{parent}) {
	    my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
	    my $kakarimoto = $indexer->get_repnames2($kihonku);
	    my $kakarisaki = $indexer->get_repnames2($kihonku->{parent});
	    my $optional_flag = ($kihonku->{fstring} =~ /<クエリ必須係り受け>/) ? 0 : 1;
	    foreach my $moto (@$kakarimoto) {
		foreach my $saki (@$kakarisaki) {
		    my $midasi = sprintf ("%s->%s", $moto, $saki);
		    my $gdf = $DFDBS_DPND->get(encode ('utf8', $midasi));

		    my $blockTypes;
		    if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
			$blockTypes = $option->{blockTypes};
		    } else {
			$blockTypes->{""} = 1;
		    }

		    foreach my $tag (keys %{$blockTypes}) {
			my $term = new Tsubaki::Term ({
			    tid => sprintf ("%s-%s", $gid, $count++),
			    text => $midasi,
			    term_type => (($optional_flag) ? 'dpnd' : 'force_dpnd'),
			    gdf => $gdf,
			    blockType => (($tag eq '') ? undef : $tag),
			    node_type => 'basic' });

			if ($optional_flag) {
			    $optionals{$term->get_id()} = $term unless (exists $optionals{$term->get_id()});
			} else {
			    push (@terms, $term);
			}
		    }
		}
	    }
	}

    }

    return (\@terms, \%optionals);
}



sub getPaintingJavaScriptCode {
    my ($result, $colorOffset) = @_;

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

	my ($synbuf, $max_num_of_words) = &_getExpressions($i, $tag, \%tid2syns, $syngraph);

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
    my ($i, $tag, $tid2syns, $syngraph) = @_;


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
#		unless ($this->{disable_synnode}) {
		    my @tids = $synnodes->tagids;
		    my $max_num_of_w = &_getPackedExpressions($i, \%synbuf, $tid2syns, \@tids, $str, $functional_word, $syngraph);
		    $max_num_of_words = $max_num_of_w if ($max_num_of_words < $max_num_of_w);
#		}
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
