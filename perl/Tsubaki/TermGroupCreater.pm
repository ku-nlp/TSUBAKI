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
use PredicateArgumentFeatureBit;
use Data::Dumper;
use Juman;

my $juman = new Juman;

my $CONFIG = Configure::get_instance();

my $DFDBS_WORD;
if ($CONFIG->{USE_WEB_DF}) {
#	tie %{$DFDBS_WORD}, 'CDB_File', $CONFIG->{COMPOUND_NOUN_DFDB_PATH} or die;
#	$DFDBS_WORD = new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
	$DFDBS_WORD = new CDB_Reader (sprintf ("%s/cdb_df_web.keymap", $CONFIG->{WORD_DFDB_PATH}));
}else{
	$DFDBS_WORD = new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
}
my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));

sub create {
    my ($result, $condition, $option) = @_;

    my ($terms, $optionals, $rep2style, $rep2rep_w_yomi, $synnode2midasi);
    if ($option->{english}) {
	# 英語用
	my %stopwords; # stop words
	if ($CONFIG->{STOPWORD_LIST_FILE} && -f $CONFIG->{STOPWORD_LIST_FILE}) {
	    if (open(STOPWORDS, $CONFIG->{STOPWORD_LIST_FILE})) {
		while (<STOPWORDS>) {
		    chomp;
		    $stopwords{$_} = 1;
		}
		close(STOPWORDS);
	    }
	}
	$rep2style = {};
	($terms, $optionals) = &createTermsFromEnglish($result, $option, $rep2style, \%stopwords);
    } else {
	# 日本語用
	my @ids = ();
	my @kihonkus = $result->tag;
	# termからハイライト用スタイルへのマップ
	$rep2style = &_getRep2Style (\@kihonkus, \@ids, $option);
	# termから表記（読み付き）へのマップ（キャッシュページをハイライトする際に利用）
	$rep2rep_w_yomi = &_getRep2RepWithYomi (\@kihonkus, \@ids, $option);
	# term（synnode）から代表表記へのマップ（根拠検索で利用）
	$synnode2midasi = &_getSynNode2Midasi (\@kihonkus, $option);

	# termのS式を生成
	($terms, $optionals) = &createTermsFromJapanese($condition, \@kihonkus, \@ids, $option);
    }

    my $root = new Tsubaki::TermGroup (
	-1,
	-1,
	-1,
	undef,
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
	    rep2rep_w_yomi => $rep2rep_w_yomi,
	    synnode2midasi => $synnode2midasi
	});

#   print $root->to_S_exp() . "\n";
    return $root;
}

# termオブジェクトを生成（英語）
sub createTermsFromEnglish {
    my ($result, $option, $rep2style, $stopwords_hr) = @_;

    # make blocktype features
    my $blockTypes = ($CONFIG->{USE_OF_BLOCK_TYPES}) ? $option->{blockTypes} : {"" => 1};
    my $blockTypeFeature = 0;
    foreach my $tag (keys %{$blockTypes}) {
	next unless ($tag =~ /MT/);
	$tag =~ s/://;
	$blockTypeFeature += $CONFIG->{BLOCK_TYPE_DATA}{$tag}{mask};
    }

    my ($terms, $optionals);
    # read from standard format
    require StandardFormat;
    my $sf = new StandardFormat();
    $sf->read_first_annotation($result);

    # word terms
    my $gid = 0;
    foreach my $id (sort {$sf->{words}{$a}{position} <=> $sf->{words}{$b}{position}} keys %{$sf->{words}}) {
	my $count = 0;
	my $color_num = $gid % scalar(@{$CONFIG->{HIGHLIGHT_COLOR}});
	my $repname = $sf->{words}{$id}{repname} ? $sf->{words}{$id}{repname} : $sf->{words}{$id}{lem};
	next if exists($stopwords_hr->{$repname}); # stop word
	$rep2style->{$repname} = sprintf("background-color: #%s; color: %s; margin:0.1em 0.25em;", $CONFIG->{HIGHLIGHT_COLOR}[$color_num], (($color_num > 4) ? 'white' : 'black'));
	my $term = new Tsubaki::Term ({
	    tid => sprintf ("%s-%s", $gid, $count++),
	    text => $repname,
	    term_type => 'word',
	    gdf => &PickDFDB($repname),
	    blockTypeFeature => $blockTypeFeature,
	    node_type => 'basic' });
	push (@{$terms}, $term);
	$gid++;
    }

    # dpnd terms
    if ($option->{flag_of_dpnd_use}) {
	foreach my $id (sort {$sf->{phrases}{$a} <=> $sf->{phrases}{$b}} keys %{$sf->{phrases}}) {
	    next if !$sf->{phrases}{$id}{head_ids}; # skip roots of English (undef)
	    my $mod_w_id = $sf->{phrases}{$id}{word_head_id}; # the word id of modifier
	    my $dep_repname = $sf->{words}{$mod_w_id}{repname} ? $sf->{words}{$mod_w_id}{repname} : $sf->{words}{$mod_w_id}{lem};
	    next unless $dep_repname;
	    next if exists($stopwords_hr->{$dep_repname}); # stop word
	    for my $head_id (@{$sf->{phrases}{$id}{head_ids}}) {
		next if $head_id eq 'c-1'; # skip roots of Japanese (-1)
		my $head_w_id = $sf->{phrases}{$head_id}{word_head_id}; # the word id of head
		my $head_repname = $sf->{words}{$head_w_id}{repname} ? $sf->{words}{$head_w_id}{repname} : $sf->{words}{$head_w_id}{lem};
		next unless $head_repname;
		next if exists($stopwords_hr->{$head_repname}); # stop word
		my $pa_feature = 0;
		if ($CONFIG->{USE_OF_DPND_FEATURES} && # predicate-argument relation if exists
		    exists($sf->{words}{$head_w_id}{arguments}) && exists($sf->{words}{$head_w_id}{arguments}{$mod_w_id})) {
		    if (exists($PredicateArgumentFeatureBit::CASE_FEATURE_BIT{$sf->{words}{$head_w_id}{arguments}{$mod_w_id}})) {
			$pa_feature += $PredicateArgumentFeatureBit::CASE_FEATURE_BIT{$sf->{words}{$head_w_id}{arguments}{$mod_w_id}};
		    }
		}
		my $count = 0;
		my $dpnd_term = sprintf('%s->%s', $dep_repname, $head_repname);
		my $term = new Tsubaki::Term ({
					       tid => sprintf ("%s-%s", $gid, $count++),
					       text => $dpnd_term,
					       term_type => 'dpnd',
					       gdf => $DFDBS_DPND->get($dpnd_term, {exhaustive => 1}), 
					       blockTypeFeature => $blockTypeFeature + $pa_feature,
					       node_type => 'basic' });
		$optionals->{$term->get_id()} = $term unless (exists $optionals->{$term->get_id()});
	    }
	}
    }

    return ($terms, $optionals);
}

# termオブジェクトを生成（日本語）
sub createTermsFromJapanese {
    my ($condition, $kihonkus, $ids, $option) = @_;

    my $tagid2df = &get_tagid2df($kihonkus, { option => $option });
    
    my ($terms, $optionals) =
	(($condition->{is_phrasal_search} > 0) ?
	 &_create4phrase ($kihonkus, $ids, "", $option) :
	 &_create (0, $kihonkus, $ids, undef, "", $tagid2df, $option));

    # 根拠検索用に「ため」や「ので」を含む文書を検索するようにする
    if ($option->{conjunctive_particle}) {
	# 指定された語に関するタームを生成
	my $termG = new Tsubaki::TermGroup();
	$termG->{gdf} = 100000000;
	foreach my $midasi (@{$option->{conjunctive_particle}}) {
	    my ($cnt, $gid) = (10000, 0);
	    my $blockTypes = ($CONFIG->{USE_OF_BLOCK_TYPES}) ? $option->{blockTypes} : {};
	    my $blockTypeFeature = 0;
	    foreach my $tag (keys %{$blockTypes}) {
		# next unless ($tag =~ /MT/);
		$tag =~ s/://;
		$blockTypeFeature += $CONFIG->{BLOCK_TYPE_DATA}{$tag}{mask};
	    }

	    my $term = new Tsubaki::Term ({
		tid => sprintf ("%s-%s", $gid, $cnt++),
		pos => 0,
		text => sprintf ("%s*", $midasi),
		term_type => 'word',
		node_type => 'basic',
		gdf => 10000000,
		blockTypeFeature => $blockTypeFeature });
	    push (@{$termG->{terms}}, $term);
	}
	unshift (@$terms, $termG);
    }

    return ($terms, $optionals);
}

sub get_tagid2df {
    my ($kihonkus, $opt) = @_;

    my %tagid2df = {};
    foreach my $i (0 .. scalar (@$kihonkus) - 1) {
	foreach my $synnodes ($kihonkus->[$i]->synnodes) {
	    foreach my $synnode ($synnodes->synnode) {
		if (&is_basic_node($synnode)) {
		    my $gdf = &_getDF ($synnode, undef, $opt);
		    $tagid2df{$i} = $gdf;
		    last;
		}
	    }
	}
    }
    return \%tagid2df;
}

# キャッシュページハイライト用に、タームからターム（読み付き）へのマップを作成
sub _getRep2RepWithYomi {
    my ($kihonkus, $ids, $option) = @_;

    my %rep2rep_w_yomi = ();
    foreach my $i (0 .. scalar (@$kihonkus) - 1) {
	foreach my $synnodes ($kihonkus->[$i]->synnodes) {
	    foreach my $synnode ($synnodes->synnode) {
		$rep2rep_w_yomi{$option->{ignore_yomi} ? &remove_yomi(lc($synnode->synid)) : lc($synnode->synid)} = $synnode->synid;
	    }
	}
    }

    return \%rep2rep_w_yomi;
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
		next if ($synnode->synid =~ /^s\d+/ && $option->{disable_synnode});
		my $key = sprintf ("%s%s", $option->{ignore_yomi} ? &remove_yomi(lc($synnode->synid)) : lc($synnode->synid), $synnode->feature);
		$rep2style{$key} = sprintf ("background-color: #%s; color: %s; margin:0.1em 0.25em;", $CONFIG->{HIGHLIGHT_COLOR}[$j], (($j > 4) ? 'white' : 'black'));
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
	    next if ($m->fstring !~ /<(?:準)?内容語>/);
	    $surf .= $m->midasi;
	}
	$midasi[$i] = $surf;

	foreach my $synnodes ($kihonkus->[$i]->synnodes()) {
	    foreach my $synnode ($synnodes->synnode()) {
		# synnode 以外は扱わない → 扱う (異表記も扱うため)
		# next unless ($synnode->synid =~ /s\d+/);

		# 読みの削除
		my $_midasi = sprintf ("%s%s", $opt->{option}{ignore_yomi} ? &remove_yomi($synnode->synid) : $synnode->synid, $synnode->feature);

		# <反義語><否定>を利用するかどうか
		if ($_midasi =~ /<反義語>/ && $_midasi =~ /<否定>/) {
#		    next unless ($opt->{option}{use_of_negation_and_antonym});
		    next unless ($opt->{option}{antonym_and_negation_expansion});
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

# フレーズ検索用にtermオブジェクトを生成
sub _create4phrase {
    my ($kihonkus, $tids, $space, $opt) = @_;

    my ($gid, $count, @terms, %optionals, %visitedKihonkus) = (0, 0, (), (), ());
    foreach my $tid (@$tids) {
	my $kihonku = $kihonkus->[$tid];
	foreach my $mrph ($kihonku->mrph) {
	    my $midasi = sprintf ("%s*", $opt->{option}{ignore_yomi} ? &remove_yomi($mrph->midasi) : $mrph->midasi);
	    my $gdf = &PickDFDB($midasi);

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
		      undef,
		      $opt
		  ));
	}

	# 係り受けタームの追加
	&_pushbackDependencyTerms(\@terms, \%optionals, $kihonku, $gid, $count, $opt) if $opt->{option}{flag_of_dpnd_use};
    }

    return (\@terms, \%optionals);
}

# termオブジェクトを生成
sub _create {
    my ($gid, $kihonkus, $tids, $parent, $space, $tagid2df, $option) = @_;

    my ($isLastKihonku, $count, @terms, %optionals, %visitedKihonkus) = (1, 0, (), (), ());
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
	my $children = &_getChildNodes (\%optionals, $group_id, $kihonkus, \@tagids, $broadest_synnodes, $space, $tagid2df, $option);

	# タームグループの作成
	my $termGroups = &_createTermGroup ($group_id, $tid, \@synnodes, $kihonku, $children, $tagid2df, { optional_flag => $is_optional_node, is_last_kihonku => $isLastKihonku, option => $option });
	$isLastKihonku = 0;

	foreach my $termGroup (@$termGroups) {
	    if ($is_optional_node) {
		$optionals{$termGroup->text()} = $termGroup unless (defined ($optionals{$termGroup->text()}));
	    } else {
		unshift (@terms, $termGroup);
	    }
	}

	# 係り受けタームの追加
	&_pushbackDependencyTerms(\@terms, \%optionals, $kihonku, $gid, $count, $option) if $option->{flag_of_dpnd_use};
    }

    return (\@terms, \%optionals);
}

# メモリ使用量減らすためにsynnodeを削除する
sub reduceSynNode {
    my ($basic_node, $synnodes, $opt) = @_;

    next unless (defined $synnodes);

    my $N = ($opt->{use_of_antonym_expansion}) ? int (0.5 * ($CONFIG->{MAX_NUMBER_OF_SYNNODES} + 1)) : $CONFIG->{MAX_NUMBER_OF_SYNNODES};

    # 各ノードのgdfを得る
    my $count = 0;
    my @newNodes = ();

    push (@newNodes, $basic_node) if (defined $basic_node);
    foreach my $node (sort {&PickDFDB($opt->{option}{ignore_yomi} ? &remove_yomi($b->synid) : $b->synid) <=> &PickDFDB($opt->{option}{ignore_yomi} ? &remove_yomi($a->synid) : $a->synid) } @$synnodes) {
	next if ($basic_node == $node);
	push (@newNodes, $node) if (defined $node);
	last if (++$count >= $N);
    }

    return \@newNodes;
}

# DFの取得
sub _getDF {
    my ($basicNd, $synNds, $opt, $tagid2df, $tid) = @_;

    # 1基本句
    if ($basicNd) {
        if ($tagid2df) {
            return $tagid2df->{$tid};
        }
        else {
            return &PickDFDB($opt->{option}{ignore_yomi} ? &remove_yomi($basicNd->synid) : $basicNd->synid, {exhaustive => 1});
        }
    # 複数基本句
    } else {
        if ($tagid2df) {
            # 複数基本句のDFの平均をとる
            my $df = 0;
            for my $tagid ($synNds->[0]->tagids) {
            $df += $tagid2df->{$tagid};
            }
            return $df / scalar($synNds->[0]->tagids);
        }
        else {
            return &PickDFDB($opt->{option}{ignore_yomi} ? &remove_yomi($synNds->[0]->synid) : $synNds->[0]->synid, {exhaustive => 1}) if (defined $synNds);
        }
    }
}

sub remove_yomi {
    my ($text) = @_;

    my @buf;
    foreach my $word (split /\+/, $text) {
	if ($word =~ /^s\d+/) { # use synnode as it is
	    push (@buf, $word);
	}
	else {
	    my ($hyouki, $yomi) = split (/\//, $word);
	    push (@buf, $hyouki);
	}
    }

    return join ("+", @buf)
}

sub is_basic_node {
    my ($synnode) = @_;

    if ($synnode->synid !~ /^s\d+/ && $synnode->feature !~ /<反義語>/) {
	return 1;
    }
    else {
	return 0;
    }
}

# 基本ノードの取得
sub getBasicNode {
    my ($synnodes) = @_;

    foreach my $synnode (@$synnodes) {
	if (&is_basic_node($synnode)) {
	    return $synnode;
	}
    }
    return undef;
}

# 文法素性の削除
sub removeSyntacticFeatures {
    my ($midasi) = @_;

    $midasi =~ s/<可能>//;
    $midasi =~ s/<尊敬>//;
    $midasi =~ s/<受身>//;
    $midasi =~ s/<使役>//;

    return $midasi;
}

# <上位語>を付けることで下位語を検索可能にする
sub expandHypernymTerm {
    my ($midasi, $_buf, $opt) = @_;

    # フレーズの場合は付けない
    unless ($midasi =~ /\*$/) {
	$midasi .= '<上位語>';
	unless (exists $opt->{remove_synids}{$midasi}) {
	    push (@$_buf, $midasi);
	}
    }
}

# 否定、反義語で拡張する
sub expandAntonymAndNegationTerms {
    my ($midasi, $_buf, $opt) = @_;
    my (@features);

    return if $midasi =~ /<反義語>/;

    if ($midasi =~ /<否定>/) { # すでに<否定>がついている場合
	$midasi =~ s/<否定>//;

	# 行く<否定> -> 行く<反義語><否定>
	push(@features, '<反義語><否定>');

	if ($opt->{option}{antonym_and_negation_expansion}) {
	    push(@features, '');
	    push(@features, '<反義語>');
	}
    }
    else {
	# (行く -> 行く<反義語>)
	push(@features, '<反義語>');

	if ($opt->{option}{antonym_and_negation_expansion}) {
	    push(@features, '<否定>');
	    push(@features, '<反義語><否定>');
	}
    }

    foreach my $feature (@features) {
	push(@$_buf, sprintf("%s%s", $midasi, $feature));
    }
}

# termを拡張する
sub termExpansion {
    my ($midasi, $opt) = @_;
    my @buf;

    # <上位語>を付与して下位語を検索可能にする
    &expandHypernymTerm($midasi, \@buf, $opt) if ($opt->{option}{hypernym_expansion});

    # 否定・反義語でタームを拡張する, 拡張されるのは最後の基本句のみ
    &expandAntonymAndNegationTerms($midasi, \@buf, $opt) if ($opt->{is_last_kihonku});

    return \@buf;
}

# termグループの作成
sub _createTermGroup {
    my ($gid, $tid, $synNds, $parent, $children, $tagid2df, $opt) = @_;

    my $basicNd = &getBasicNode($synNds);
    $synNds = &reduceSynNode($basicNd, $synNds, $opt) if ($CONFIG->{MAX_NUMBER_OF_SYNNODES});
    my $gdf = &_getDF ($basicNd, $synNds, $opt, $tagid2df, $tid);

    my @midasis = ();
    my @midasi_lengths = ();
    foreach my $synNd (@$synNds) {
	# print $opt->{option}{remove_synids} ." " . $synNd->synid . "\n";
	next if (exists $opt->{option}{remove_synids}{$synNd->synid});

	my $_midasi = sprintf ("%s%s", $opt->{option}{ignore_yomi} ? &remove_yomi($synNd->synid) : $synNd->synid, $CONFIG->{USE_OF_FEATURE} ? $synNd->feature : '');
	my $_midasi_length = 1;

	# SynGraphが返す<反義語>ノードは利用する必要はない
	if ($_midasi =~ /<反義語>/) {
	    next;
	}

	# SYNノードを利用しない場合
	my $is_basic_node = &is_basic_node($synNd);
	if ($opt->{option}{disable_synnode} && !$is_basic_node) {
	    next;
	}

	# 文法素性の削除
	$_midasi = &removeSyntacticFeatures($_midasi);

	push(@midasis, $_midasi);
	# SYNノードがカバーする基本句数
	if (!$is_basic_node) {
	    $_midasi_length = scalar($synNd->tagids);
	}
	push(@midasi_lengths, $_midasi_length);

	# 上位語や否定によってタームを拡張する
	if (!$opt->{english} && !$opt->{option}{disable_synnode}) { # 日本語のみ
	    my $_midasis = &termExpansion($_midasi, $opt);
	    if (@$_midasis) { 
		push(@midasis, @$_midasis);
		push(@midasi_lengths, $_midasi_length);
	    }
	}
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
	    ((defined $basicNd) ? ($opt->{option}{ignore_yomi} ? &remove_yomi($basicNd->synid) : $basicNd->synid) : ''),
	    \@midasis,
	    \@midasi_lengths,
	    $parent,
	    $children,
	    $opt
	    );

	my @__buf = (); push (@__buf, $tg);
	return \@__buf;
    }
}

# もっとも大きい（語数の多い）synnodeを獲得
sub _getBroadestSynNode {
    my ($parent, $kihonku, $ids) = @_;

    my $broadest_synnodes;
    foreach my $synnodes ($kihonku->synnodes) {
	last if ($synnodes == $parent);

	# synnodeが交差する場合は、交差しなくなるまで子をだどる
	# 例) 水の中に潜る -> s22145:水中, s10424:中に潜る

	# 間に要素の入るsynnodeは無視
	# 例) 「検索技術の情報工学者」の「技術」「者」から生成される「技術者」
	my $node = ($synnodes->synnode)[0];
	my $head = ($node->tagids)[0];
	my $tail = ($node->tagids)[-1];
	my $size = scalar($node->tagids);
	next if ($ids->[0] > $head || $tail - $head + 1 != $size);

	$broadest_synnodes = $synnodes;
    }

    return $broadest_synnodes;
}

sub _getChildNodes {
    my ($optionals, $group_id, $kihonkus, $tagids, $broadest_synnodes, $space, $tagid2df, $option) = @_;

    my $children = undef;
    if (scalar (@$tagids) > 1) {
	my $_optionals;
	($children, $_optionals) = &_create ($group_id, $kihonkus, $tagids, $broadest_synnodes, $space ."\t", $tagid2df, $option);
	foreach my $k (keys %$_optionals) {
	    $optionals->{$k} = $_optionals->{$k} unless (exists ($optionals->{$k}));
	}
    }

    return $children;
}

sub appendDpndFeature {
    my ($midasi, $kakarimoto, $kakarisaki, $index) = @_;

    my $isSurfForm = 0;
    if ($kakarimoto =~ /\*$/) {
	chop $kakarimoto;
	chop $kakarisaki;
	$isSurfForm = 1;
    }

    my $flag_saki = 1;
    my $featureBit = 0;
    my $case = 'その他';
    my @dpndTypes = ();

    my $isRentai = ($index->{kakarimoto_kihonku_fstring} =~ /<係:連格>/) ? 1: 0;
    my $mrphF    = $index->{kakarisaki_fstring};

    my $kihonkuF = $index->{kakarisaki_kihonku_fstring};
    my $kakarimotoSurf = $index->{kakarimoto_surf};
    my $suffix   = '';
    if ($isRentai) {
	$mrphF    = $index->{kakarimoto_fstring};
	$kihonkuF = $index->{kakarimoto_kihonku_fstring};
	$kakarimotoSurf = $index->{kakarisaki_surf};
	push (@dpndTypes, '連体');
	# 連体修飾の場合は係り元と係り先を入れ替える
	my $_tmp = $kakarimoto;
	$kakarimoto = $kakarisaki;
	$kakarisaki = $_tmp;
	if ($isSurfForm) {
	    $midasi = sprintf ("%s*->%s*", $kakarimoto, $kakarisaki);
	} else {
	    $midasi = sprintf ("%s->%s", $kakarimoto, $kakarisaki);
	}
    } else {
#	$case = 'ノ' if ($index->{kakarimoto_kihonku_fstring} =~ /<係:(?:ノ格|文節内)>/);
#	$case = 'ノ' if ($index->{kakarimoto_kihonku_fstring} =~ /<係:ノ格>/);
    }

    my ($CASE_F_ID, $CASE_ELMT);
    if ($kihonkuF =~ /<格構造:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
	$CASE_F_ID = $1;
	$CASE_ELMT = $2;
    }
    elsif ($kihonkuF =~ /<格解析結果:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
	$CASE_F_ID = $1;
	$CASE_ELMT = $2;
    }
    my ($N_CASE_F_ID, $N_CASE_ELMT);
    if ($kihonkuF =~ /<正規化格解析結果-0:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
	$N_CASE_F_ID = $1;
	$N_CASE_ELMT = $2;
    }

    if ($CASE_F_ID =~ m|\+(?:さ)?せる/(?:さ)?せる|) {
	push (@dpndTypes, '使役');
	$suffix .= '<使役>';
    }
    if ($CASE_F_ID =~ m|\+(?:ら)?れる/(?:ら)?れる|) {
	push (@dpndTypes, '受動');
	$suffix .= '<受動>';
    }

    # 正規化格解析
    foreach my $caseElement (split (";", $N_CASE_ELMT)) {
	my ($_case, $type, $label, $eid) = split ("/", $caseElement);

	# チェック
	next unless ($label =~ /[$kakarimoto|$kakarimotoSurf]$/);

	if ($N_CASE_F_ID =~ m!^([^/]+)!) {
	    $kakarisaki = $1;
	    if ($isSurfForm) {
		$midasi = sprintf ("%s*->%s*", $kakarimoto, $kakarisaki);
	    } else {
		$midasi = sprintf ("%s->%s", $kakarimoto, $kakarisaki);
	    }
	}

	if ($type eq 'N' && !$isRentai) {
	    push (@dpndTypes, '未格');
	}
	elsif ($type eq 'O') {
	    push (@dpndTypes, '省略');
	}
	$case = $_case;
	last;
    }

    if ($case eq 'その他') {
	# 格構造
	foreach my $caseElement (split (";", $CASE_ELMT)) {
	    my ($_case, $type, $label, $eid) = split ("/", $caseElement);

	    # チェック
	    next unless ($label =~ /[$kakarimoto|$kakarimotoSurf]$/);

	    if (!$isRentai && $index->{kakarimoto_kihonku_fstring} =~ /<係:未格>/) {
		push (@dpndTypes, '未格');
	    }
	    elsif ($type eq 'O') {
		push (@dpndTypes, '省略');
	    }

	    # <使役><受動>をタームに付与
	    $midasi .= $suffix;
	    $case = $_case;
	    last;
	}
    }

    push (@dpndTypes, '自動')   if ($mrphF =~ /<自他動詞:他/);
    push (@dpndTypes, '授動詞') if ($mrphF =~ /<授受動詞:受/);

    my $featureBit = $PredicateArgumentFeatureBit::CASE_FEATURE_BIT{$case};
    my @featureBuf = ($case);
    foreach my $dpndType (@dpndTypes) {
	$featureBit |= $PredicateArgumentFeatureBit::DPND_TYPE_FEATURE_BIT{$dpndType};
	push (@featureBuf, $dpndType);
    }
    # print "*** " . $midasi . " " . join (",", @featureBuf) . " $featureBit\n";

    return ($midasi, $featureBit);
}

# 係り受けタームの追加
sub _pushbackDependencyTerms {
    my ($terms, $optionals, $kihonku, $gid, $count, $option) = @_;

    # 係り受けを追加
    my $indexer = new Indexer({ignore_yomi => $option->{ignore_yomi}});
    if (defined $kihonku->parent && $kihonku->fstring !~ /<クエリ削除係り受け>/) {
	my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
	my $kakarimoto = $indexer->get_repnames2($kihonku);
	my $kakarisaki = $indexer->get_repnames2($kihonku->parent);
	my $is_optional_node = ($kihonku->fstring =~ /<クエリ必須係り受け>/) ? 0 : (($option->{force_dpnd}) ? 0 : 1);
	my @_terms;

	
	my $index;
	$index->{kakarimoto_kihonku_fstring} = $kihonku->fstring;
	$index->{kakarisaki_kihonku_fstring} = $kihonku->parent->fstring;
	$index->{kakarisaki_fstring} = ($kihonku->parent->mrph)[0]->fstring;
	$index->{kakarimoto_fstring} = ($kihonku->mrph)[0]->fstring;
	$index->{kakarisaki_surf} = $option->{ignore_yomi} ? &remove_yomi(($kihonku->parent->mrph)[0]->midasi) : ($kihonku->parent->mrph)[0]->midasi;
	$index->{kakarimoto_surf} = $option->{ignore_yomi} ? &remove_yomi(($kihonku->mrph)[0]->midasi) : ($kihonku->mrph)[0]->midasi;

	foreach my $moto (@$kakarimoto) {
	    foreach my $saki (@$kakarisaki) {
		my $_midasi = sprintf ("%s->%s", $moto, $saki);
		my ($midasi, $feature) = &appendDpndFeature($_midasi, $moto, $saki, $index);

		my $gdf = $DFDBS_DPND->get($midasi, {exhaustive => 1});
		my $blockTypes = ($CONFIG->{USE_OF_BLOCK_TYPES}) ? $option->{blockTypes} : {"" => 1};
		my $blockTypeFeature = 0;
		foreach my $tag (keys %{$blockTypes}) {
		    $tag =~ s/://;
		    $blockTypeFeature += $CONFIG->{BLOCK_TYPE_DATA}{$tag}{mask};
		}

		my $term = new Tsubaki::Term ({
		    tid => sprintf ("%s-%s", $gid, $count++),
		    text => $CONFIG->{USE_OF_DPND_FEATURES} ? $midasi : $_midasi,
		    term_type => (($is_optional_node) ? 'dpnd' : 'force_dpnd'),
		    gdf => $gdf,
		    blockTypeFeature => $blockTypeFeature + ($CONFIG->{USE_OF_DPND_FEATURES} ? $feature : 0),
		    node_type => 'basic' });

		if ($is_optional_node) {
		    $optionals->{$term->get_id()} = $term unless (exists $optionals->{$term->get_id()});
		} else {
		    push (@_terms, $term);
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

sub PickDFDB{
	my ($string, $option) = @_;
	if($CONFIG->{USE_WEB_DF}){
		if ($string =~ m!^([^/]+).*(v|a)$!){
			return $DFDBS_WORD->get(&get_original_str($1), $option);
        }elsif ($string =~ m!^([^/]+)!){
			return $DFDBS_WORD->get($1, $option);
		}else{
			return $DFDBS_WORD->get($string, $option);
		}
	}
	return $DFDBS_WORD->get($string, $option);
}

sub get_original_str {
    my ($str) = @_;
    my $result = $juman->analysis($str);
    my $first_mrph = ($result->mrph)[0];
    my $rep = $first_mrph->repname;
    if ($rep =~ m!^([^/]+)!) {
    return $1;
    }
    else {
    return $rep;
    }
}


1;
