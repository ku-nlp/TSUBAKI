package QueryParser;

# $Id$

# 検索クエリを内部形式に変換するクラス

use strict;
use Encode;
use utf8;
use Unicode::Japanese;
use KNP;
use Indexer;
use QueryKeyword;
use Configure;
use CDB_File;
use Query;
use Dumper;
use CDB_Reader;
use Tsubaki::TermGroupCreater;


my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class, $opts) = @_;

    print "constructing QueryParser object...\n" if ($opts->{debug});

    # デフォルト値以外のパラメータが指定されている場合は、新たにKNPをnewする
    if ($opts->{KNP_COMMAND} || $opts->{JUMAN_COMMAND} || $opts->{JUMAN_RCFILE} || $opts->{KNP_RCFILE} ||
	$opts->{KNP_OPTIONS} || $opts->{use_of_case_analysis} || $opts->{use_of_NE_tagger}) {
	# KNPオブジェクトの構築
	&createKNPObj($opts);
    }

    # Indexerオブジェクトの構築
    my ($indexer, $indexer_genkei) = &createIndexerObj($opts);

    # QueryParserオブジェクトの構築
    my $this = {
	KNP => $CONFIG->{KNP},
	INDEXER => $indexer,
	INDEXER_GENKEI => $indexer_genkei,
	DFDBS_WORD => (-e $opts->{DFDB_DIR}) ? new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $opts->{DFDB_DIR})) : undef,
	DFDBS_DPND => (-e $opts->{DFDB_DIR}) ? new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $opts->{DFDB_DIR})) : undef,
	OPTIONS => {
	    trimming => $opts->{QUERY_TRIMMING},
	    use_of_block_types => defined($opts->{USE_OF_BLOCK_TYPES}) ? $opts->{USE_OF_BLOCK_TYPES} : $CONFIG->{USE_OF_BLOCK_TYPES}, # newに指定された設定は、CONFIGよりも優先
	    is_cpp_mode => defined($opts->{IS_CPP_MODE}) ? $opts->{IS_CPP_MODE} : $CONFIG->{IS_CPP_MODE}, # newに指定された設定は、CONFIGよりも優先
	    syngraph => undef,
	    call_from_api => $opts->{call_from_api}
	}
    };


    print "QueryParser object construction is OK.\n\n" if ($opts->{debug});
    bless $this;
}

# KNPオブジェクトの構築
sub createKNPObj {
    my ($opts) = @_;

    $opts->{KNP_COMMAND}   = $CONFIG->{KNP_COMMAND}   unless ($opts->{KNP_COMMAND});
    $opts->{JUMAN_COMMAND} = $CONFIG->{JUMAN_COMMAND} unless ($opts->{JUMAN_COMMAND});
    $opts->{JUMAN_RCFILE}  = $CONFIG->{JUMAN_RCFILE}  unless ($opts->{JUMAN_RCFILE});
    $opts->{KNP_RCFILE}    = $CONFIG->{KNP_RCFILE}    unless ($opts->{KNP_RCFILE});
    $opts->{KNP_OPTIONS}   = $CONFIG->{KNP_OPTIONS}   unless ($opts->{KNP_OPTIONS});

    # クエリを格解析する
    if ($opts->{use_of_case_analysis}) {
	@{$opts->{KNP_OPTIONS}} = grep {$_ ne '-dpnd'} @{$opts->{KNP_OPTIONS}};
    }

    # クエリに対して固有表現解析する際は、オプションを追加
    if ($opts->{use_of_NE_tagger}) {
	push(@{$opts->{KNP_OPTIONS}}, '-ne-crf');
	push(@{$opts->{KNP_OPTIONS}}, '-ne-cache');
    }

    if ($opts->{debug}) {
	print "* jmn -> $opts->{JUMAN_COMMAND}\n";
	print "* knp -> $opts->{KNP_COMMAND}\n";
	print "* knprcflie -> $opts->{KNP_RCFILE}\n";
	print "* knpoption -> ", join(",", @{$opts->{KNP_OPTIONS}}) . "\n\n";

	print "* re-create knp object...";
    }

    $CONFIG->{KNP} = new KNP(
	-Command => $opts->{KNP_COMMAND},
	-Option => join(' ', @{$opts->{KNP_OPTIONS}}),
	-Rcfile => $opts->{KNP_RCFILE},
	-JumanRcfile => $opts->{JUMAN_RCFILE},
	-JumanCommand => $opts->{JUMAN_COMMAND}
	);

    print " done.\n" if ($opts->{debug});
}

# Indexerオブジェクトの構築
sub createIndexerObj {
    my ($opts) = @_;

    my ($indexer, $indexer_genkei);
    unless ($opts->{STOP_WORDS}) {
	$indexer = new Indexer({ignore_yomi => $opts->{ignore_yomi}});
	$indexer_genkei = new Indexer({ignore_yomi => $opts->{ignore_yomi}, genkei => 1});
    } else {
	# ストップワードの処理
	my %stop_words;
	foreach my $word (@{$opts->{STOP_WORDS}}) {
	    # 代表表記ではない場合、代表表記を得る
	    unless ($word =~ /\//) {
		my $result = $CONFIG->{KNP}->parse($word);

		if (scalar ($result->mrph) == 1) {
		    $word = ($result->mrph)[0]->repname;
		}
		# 一形態素ではない場合、Parse Errorの可能性あり
		else {
		    print STDERR "$word: Parse Error?\n";
		}
	    }
	    $stop_words{$word} = 1;
	}
	$indexer = new Indexer({
	    STOP_WORDS => \%stop_words,
	    ignore_yomi => $opts->{ignore_yomi} });
	$indexer_genkei = new Indexer({
	    STOP_WORDS => \%stop_words,
	    ignore_yomi => $opts->{ignore_yomi},
	    genkei => 1 });
    }

    return ($indexer, $indexer_genkei);
}

# 検索クエリを解析(英語)
sub parse_for_english {
    my ($this, $qks_str, $opt) = @_;

    my $isPhrasalSearch = 0;
    # フレーズ検索かどうかのチェック
    if ($qks_str =~ /^'.+'$/) {
	$isPhrasalSearch = 1;
	$qks_str =~ s/^\'//;
	$qks_str =~ s/\'$//;
    }

    my %param = ();
    my @words = ();
    my $qid = 0;
    my $gid = 0;
    my $num_of_words = 0;
    my %qid2gid = ();
    my %qid2qtf = ();

    my $lemmatizer;
    if ($opt->{lemma}) {
	require Lemmatize;
	$lemmatizer = new Lemmatize();
    }

    foreach my $word (split (" ", $qks_str)) {
	my @terms;

	print $word . " -> " if ($opt->{debug});
	if ($opt->{lemma}) {
	    my $lemmatized_word = $lemmatizer->lemmatize($word, '');
	    $word = (defined $lemmatized_word) ? $lemmatized_word : $word;
	    $word .= "*";
	    $word = lc($word);
	}

	print $word . "\n" if ($opt->{debug});

	my $term = {
	    requisite => 1,
	    string => $word,
	    qid => $qid,
	    qid => $gid,
	    syngraph => 1
	    };
	$qid2gid{$qid} = $gid;
	$qid2qtf{$qid} = 1;

	$param{qid2df}->{$qid++} = 1;
	push (@terms, $term);

	# 同義語を考慮したい場合は@termに追加する

	push (@words, \@terms);
	$gid++;
	$num_of_words++;
    }

    push (@{$param{keywords}},
	  {
	      near => $num_of_words,
	      logical_cond_qkw => 'AND',
	      syngraph => 1,
	      words => \@words,
	      keep_order => 1
	      });
    $param{qid2gid} = \%qid2gid;
    $param{qid2qtf} = \%qid2qtf;
    my $query = new Query(\%param);

    return $query;
}


sub _analyzeSearchCondition {
    my ($this, $search_expression, $opt) = @_;

    ##############
    # デフォルト値
    ##############

    # 検索語に含まれる単語間の論理条件
    my $logical_cond_qkw = 'AND';
    # クエリに制約(近接およびフレーズ)が指定されていなければ~$CONFIG->{DEFAULT_APPROXIMATE_DIST}wをつける
    my $approximate_dist = ($opt->{near} > 0) ? $opt->{near} : $CONFIG->{DEFAULT_APPROXIMATE_DIST};
    my $approximate_order = 0;
    my $force_dpnd = $opt->{force_dpnd};
    my $sentence_flag = -1;
    my $is_phrasal_search = -1;
    my $used_indexer = $this->{INDEXER};

    # フレーズ検索かどうかの判定
    if ($search_expression =~ /^"(.+)?"$/) {
	$is_phrasal_search = 1;
	$approximate_order = 1;
	$search_expression = $1;
	$approximate_dist = 1;
	$used_indexer = $this->{INDEXER_GENKEI} if ($CONFIG->{IS_NICT_MODE});
	# フレーズ検索ではSynNodeを利用しない
	$opt->{disable_synnode} = 1;
    }
    # 制約がしていされているかどうかの判定
    elsif ($search_expression =~ /^(.+)?~(.+)$/) {
	$search_expression = $1;
	# 検索制約の取得
	my $constraint_tag = $2;

	# 近接制約
	if ($constraint_tag =~ /^(\d+)(W|S)$/i) {
	    $logical_cond_qkw = 'AND';
	    $sentence_flag = 1 if ($2 =~ /S/i);
	    $approximate_dist = $1;
	    $approximate_order = 1 if ($2 eq 'S' || $2 eq 'W');
	}
	# 論理条件制約
	elsif ($constraint_tag =~ /(AND|OR)/) {
	    $logical_cond_qkw = $1;
	    $approximate_dist = 0;
	}
	# 係り受け強制制約
	elsif ($constraint_tag =~ /FD/) {
	    $logical_cond_qkw = 'AND';
	    $force_dpnd = 1;
	}
    }

    return ($search_expression,
	    $logical_cond_qkw,
	    $approximate_dist,
	    $approximate_order,
	    $force_dpnd,
	    $sentence_flag,
	    $is_phrasal_search,
	    $used_indexer);

}

# 検索表現の正規化を行う
sub _normalizeSearchExpression {
    my ($this, $search_expression) = @_;

    # 半角アスキー文字列を全角に置換する
    $search_expression = Unicode::Japanese->new($search_expression)->h2z->getu;

    # 記号等の正規化
    $search_expression =~ s/−/−/g; # FULLWIDTH HYPHEN-MINUS (U+ff0d) -> MINUS SIGN (U+2212)
    $search_expression =~ s/〜/〜/g; # FULLWIDTH TILDE (U+ff5e) -> WAVE DASH (U+301c)
    $search_expression =~ s/‖/‖/g; # PARALLEL TO (U+2225) -> DOUBLE VERTICAL LINE (U+2016)
    $search_expression =~ s/¢/¢/g;  # FULLWIDTH CENT SIGN (U+ffe0) -> CENT SIGN (U+00a2)
    $search_expression =~ s/£/£/g;  # FULLWIDTH POUND SIGN (U+ffe1) -> POUND SIGN (U+00a3)
    $search_expression =~ s/¬/¬/g;  # FULLWIDTH NOT SIGN (U+ffe2) -> NOT SIGN (U+00ac)
    $search_expression =~ s/—/—/g; # EM DASH (U+2014) -> HORIZONTAL BAR (U+2015)
    $search_expression =~ s/¥/¥/g;  # YEN SIGN (U+00a5) -> FULLWIDTH YEN SIGN (U+ffe5)

    return $search_expression;
}


# 言語解析
sub _linguisticAnalysis {
    my ($this, $search_expression, $opt) = @_;

    unless ($search_expression) {
	print "Empty query !<BR>\n";
	exit(1);
    }

    if ($opt->{english}) {
    } else {
	# 検索表現を構文解析する
	my $knpresult = $this->_runKNP($search_expression, $opt);

	# クエリ処理を適用する
	$this->_runQueryProcessing($knpresult, $opt) if ($opt->{telic_process} || $opt->{CN_process} || $opt->{NE_process} || $opt->{modifier_of_NE_process});
	$this->{knp_result} = $knpresult;


	if ($opt->{syngraph}) {
	    $this->_setSynGraphObj();
	    # SynGraphで解析する
	    return $this->_runSynGraph($knpresult, $opt);
	} else {
	    return $knpresult;
	}
    }
}

# 構文解析
sub _runKNP {
    my ($this, $search_expression, $opt) = @_;

    my $knpresult;
#    try {
	$knpresult = $CONFIG->{KNP}->parse($search_expression);
#    }
#    catch Error with {
# 	my $err = shift;
# 	print "Bad query: $search_expression<BR>\n";
# 	print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
# 	print "Dumpping messages of KNP object is following.<BR>\n";
# 	print Dumper::dump_as_HTML($CONFIG->{KNP}) . "<BR>\n";
#	exit(1);
#    };
    $this->{logger}->setTimeAs('KNP', '%.3f') if (defined $this->{logger});

    unless (defined $knpresult) {
	print "Can't parse the query: $search_expression<BR>\n";
	exit(1);
    }

    return $knpresult;
}

# SynGraphで解析
sub _runSynGraph {
    my ($this, $knpresult, $opt) = @_;

    # SynGraphのオプションを設定
    # Wikipedia のエントリになっている表現に対しては同義語展開を行わない
    $opt->{syngraph_option}{no_attach_synnode_in_wikipedia_entry} = 1;
    $opt->{syngraph_option}{attach_wikipedia_info} = 1;
    $opt->{syngraph_option}{wikipedia_entry_db} = $CONFIG->{WIKIPEDIA_ENTRY_DB};
    $opt->{syngraph_option}{regist_exclude_semi_contentword} = 1;
    $opt->{syngraph_option}{relation} = 0;
    $opt->{syngraph_option}{antonym} = 1;
    $opt->{syngraph_option}{hypocut_attachnode} = 9;

    $knpresult->set_id(0);
    my $synresult = $this->{SYNGRAPH}->OutputSynFormat($knpresult, $opt->{syngraph_option}, $opt->{syngraph_option});

    $this->{syn_result} = new KNP::Result($synresult);
    $this->{logger}->setTimeAs('SynGraph', '%.3f') if (defined $this->{logger});

    return $this->{syn_result};
}

# クエリ処理の適用
sub _runQueryProcessing {
    my ($this, $knpresult, $opt) = @_;

    require Tsubaki::QueryAnalyzer;

    my $analyzer = new Tsubaki::QueryAnalyzer($opt);
    $analyzer->analyze($knpresult,
		       {
			   end_of_sentence_process => $opt->{end_of_sentence_process},
			   telic_process => $opt->{telic_process},
			   CN_process => $opt->{CN_process},
			   NE_process => $opt->{NE_process},
			   modifier_of_NE_process => $opt->{modifier_of_NE_process}
		       });
    $this->{logger}->setTimeAs('QueryAnalyzer', '%.3f') if (defined $this->{logger});

    $this->{knp_result} = $knpresult;
}

# QueryKeywordオブジェクトの構築
sub createQueryKeywordObj {
    my ($this, $_search_expression, $opt) = @_;

    # 検索表現の解析
    my ($search_expression,
	$logical_cond_qkw,
	$approximate_dist,
	$approximate_order,
	$force_dpnd,
	$sentence_flag,
	$is_phrasal_search,
	$used_indexer) = $this->_analyzeSearchCondition($_search_expression, $opt);

    # 検索表現の正規化
    $search_expression = $this->_normalizeSearchExpression($search_expression);

    # フレーズ検索の場合はSynGraphを適用しない
    $opt->{syngraph} = 1 if ($is_phrasal_search > 0);


    # 言語解析
    my $result = $this->_linguisticAnalysis($search_expression, $opt);


    if ($this->{OPTIONS}{is_cpp_mode}) {
	my %condition = ();
	$condition{force_dpnd}        = $force_dpnd;
	$condition{is_phrasal_search} = $is_phrasal_search;
	$condition{approximate_order} = $approximate_order;
	$condition{approximate_dist}  = $approximate_dist;
	$condition{logical_cond_qkw}  = $logical_cond_qkw;

	return &Tsubaki::TermGroupCreater::create(
	    $result,
	    \%condition,
	    $opt);
    }
    else {
	$opt->{indexer} = $used_indexer;
	if ($CONFIG->{IS_ENGLISH_VERSION}) {
	    return $this->parse_for_english($search_expression, $opt);
	} else {
	    my $qk = new QueryKeyword(
		$search_expression,
		$sentence_flag,
		$is_phrasal_search,
		$approximate_dist,
		$approximate_order,
		$force_dpnd,
		$logical_cond_qkw,
		$opt);
	    
	    return $qk;
	}
    }
}

# 必要であればSynGraphをnewし、メンバ変数として保持する
sub _setSynGraphObj {
    my ($this, $opt) = @_;

    $this->{OPTIONS}{syngraph} = $opt->{syngraph};
    if ($opt->{SYNGRAPH}) {
	$this->{SYNGRAPH} = $opt->{SYNGRAPH};
    } else {
	$this->{SYNGRAPH} = Configure::getSynGraphObj();
    }
    $opt->{logger}->setTimeAs('new_syngraph', '%.3f') if ($opt->{logger});
}

# $gid をふり直す
sub setGroupID {
    my ($this, $qks) = @_;

    foreach my $qk (@$qks) {
	my $gid = 0;
	my %str2gid = ();
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{gid} = $gid;
		$str2gid{$rep->{string}} = $gid;
	    }
	    $gid++;
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		my ($moto, $saki);
		if ($this->{OPTIONS}{use_of_block_types}) {
		    my ($blocktag);
		    if ($CONFIG->{IS_NICT_MODE}) { # blocktype is attached backward if NICT
			($moto, $saki, $blocktag) = ($rep->{string} =~ /^(.+?)\-\>(.+(:..))$/);
			$moto .= $blocktag; # add blocktype to also moto
		    }
		    else {
			($moto, $blocktag, $saki) = ($rep->{string} =~ /^((..:).+?)\-\>(.+)$/);
			$saki = $blocktag . $saki; # add blocktype to also saki
		    }
		}
		else {
		    ($moto, $saki) = ($rep->{string} =~ /^(.+?)\-\>(.+)$/);
		}
		my $moto_gid = $str2gid{$moto};
		my $saki_gid = $str2gid{$saki};
		$rep->{gid} = sprintf ("%d/%d", $moto_gid, $saki_gid);
	    }
	}
    }
}

# プロパティ値のセット
sub setProperties {
    my ($this, $qks, $opt) = @_;

    # $gid をふり直す
    $this->setGroupID($qks);

    my ($qid, $color, $gid_prefix, $properties, $styleBuf) = (0, 0, 0, (), ());
    for (my $gid_prefix = 0; $gid_prefix < scalar(@$qks); $gid_prefix++) {
	my $qk = $qks->[$gid_prefix];
	foreach my $type (('words', 'dpnds')) {
	    foreach my $reps (@{$qk->{$type}}) {
		foreach my $rep (@{$reps}) {
		    # グループIDを検索キーワード毎に異なるようにする
		    if ($type eq 'words') {
			$rep->{gid} = "$gid_prefix.$rep->{gid}";
		    } else {
			my ($child, $parent) = split("/", $rep->{gid});
			$rep->{gid} = "$gid_prefix.$child/$gid_prefix.$parent";
		    }

		    $properties->{rep2qid}{$rep->{string}} = $qid; $properties->{qid2rep}{$qid} = $rep->{string};
		    $properties->{rep2gid}{$rep->{string}} = $rep->{gid}; $properties->{qid2gid}{$qid} = $rep->{gid};

		    $properties->{qid2df}{$qid} = $this->get_DF($rep->{string});
		    $properties->{qid2qtf}{$qid} = $rep->{freq};
		    push(@{$properties->{gid2qids}{$rep->{gid}}}, $qid);

		    # ブロックタイプを考慮する場合は、ブロックの重みを考慮する
		    if ($this->{OPTIONS}{use_of_block_types}) {
			foreach my $tag (@{$CONFIG->{BLOCK_TYPE_KEYS}}) {
			    $properties->{qid2qtf}{$qid} *= $CONFIG->{BLOCK_TYPE_DATA}{$tag}{weight} if ($rep->{string} =~ /\Q$tag\E:/);
			}
		    }

		    # qid, gdf の設定
		    ($rep->{qid}, $rep->{df}, $rep->{gdf}) = ($qid, $properties->{qid2df}{$qid}, $properties->{qid2df}{$qid});

		    # 係り先のタームのqidへのマップを保持
		    if ($type eq 'dpnds') {
			my ($kakarimoto, $kakarisaki) = split('->', $rep->{string});
			my ($kakarimoto_qid, $kakarisaki_qid) = ($properties->{rep2qid}{$kakarimoto}, $properties->{rep2qid}{$kakarisaki});
			$rep->{kakarimoto_qid} = $kakarimoto_qid; $rep->{kakarimoto_gid} = $properties->{rep2gid}{$kakarimoto};
			$rep->{kakarisaki_qid} = $kakarisaki_qid; $rep->{kakarisaki_gid} = $properties->{rep2gid}{$kakarisaki};
			push(@{$properties->{dpnd_map}{$properties->{rep2qid}{$kakarimoto}}}, {kakarisaki_qid => $kakarisaki_qid, dpnd_qid => $qid});
		    }

		    # 基本ノードであれば文書頻度を保存する(SYNノードの文書頻度は基本ノードの文書頻度とするため)
		    $properties->{gid2df}{$rep->{gid}} = $rep->{df} if ($rep->{isBasicNode});
		    $qid++;

		    # スニペットでハイライト表示する際のスタイルを設定
		    next if ($qk->{is_phrasal_search} > 0 || $type eq 'dpnds');

		    if (exists $styleBuf->{$rep->{string}}) {
			$rep->{stylesheet} = $styleBuf->{$rep->{string}};
		    } else {
			$rep->{stylesheet} = sprintf ("background-color: %s; color: %s; margin:0.1em 0.25em;", $CONFIG->{HIGHLIGHT_COLOR}[$color], (($color > 4) ? 'white' : 'black'));
			$styleBuf->{$rep->{string}} = $rep->{stylesheet};
		    }
		}
		$color = (++$color % scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
	    }
	}
    }

    # 後処理
    $properties = $this->_postprocess($qks, $properties, $opt);

    return $properties;
}

# 後処理
sub _postprocess {
    my ($this, $qks, $properties, $opt) = @_;

    if ($CONFIG->{MAX_NUMBER_OF_SYNNODES}) {
	foreach my $qk (@$qks) {
	    $qk->reduceSynnodes($opt->{antonym_and_negation_expansion});
	}
    }

    # SynNodeのgdfは基本ノードのgdfにする
    if ($opt->{syngraph}) {
	foreach my $qk (@$qks) {
	    foreach my $type (('words', 'dpnds')) {
		foreach my $reps (@{$qk->{$type}}) {
		    foreach my $rep (@{$reps}) {
			my $df_of_basic_node = $properties->{gid2df}{$rep->{gid}};
			$df_of_basic_node = 0 unless (defined $df_of_basic_node);
			$properties->{qid2df}{$rep->{qid}} = $df_of_basic_node;
			$rep->{df} = $df_of_basic_node;
			$rep->{gdf} = $df_of_basic_node;
		    }
		}
	    }
	}
    }

    return $properties;
}

# 検索クエリを解析
sub parse {
    my ($this, $qks_str, $opt) = @_;

    # 必要であればSynGraphをnewし、メンバ変数として保持する
    $this->_setSynGraphObj() if ($opt->{syngraph});

    my @qks = ();
    my @sexps = ();
    my $delim = ($opt->{no_use_of_Zwhitespace_as_delimiter}) ? "(?: )" : "(?: |　)+";
    my $rawstring;
    my $rep2style;
    my $result;
    # $delimで区切る
    foreach my $search_expression (split(/$delim/, $qks_str)) {
	# 空文字はスキップ
	next if ($search_expression eq '');

	# サイト指定検索かどうかの判定
	if ($search_expression =~ /^site:(.+)$/) {
	    $opt->{site} = $1;
	    next;
	}

	# QueryKeywordオブジェクトの構築
	my $qk = $this->createQueryKeywordObj($search_expression, $opt);

	if ($this->{OPTIONS}{is_cpp_mode}) {
	    push (@sexps, $qk->to_S_exp());
	    $rawstring = $qks_str;
	    $result = $qk->{result};
	    while (my ($k, $v) = each %{$qk->{rep2style}}) {
		$rep2style->{$k} = $v;
	    }
	}
	elsif ($CONFIG->{FORCE_APPROXIMATE_BTW_EXPRESSIONS} && scalar(@qks) > 0) {
  	    push (@{$qks[0]->{words}}, @{$qk->{words}}) if (scalar(@{$qk->{words}}) > 0);
  	    push (@{$qks[0]->{dpnds}}, @{$qk->{dpnds}}) if (scalar(@{$qk->{dpnds}}) > 0);
  	    $qks[0]->{rawstring} .= (" " . $qk->{rawstring});
  	} else {
	    push(@qks, $qk);
  	    $rawstring .= (" " . $qk->{rawstring});
  	}
    }
    # QueryKeyword作成にかかる時間を測定
    $opt->{logger}->setTimeAs('make_qks', '%.3f') if ($opt->{logger});

    # プロパティ値のセット
    my $properties = $this->setProperties(\@qks, $opt);

    # 検索クエリを表す構造体
    my $ret = new Query({
	keywords => \@qks,
	logical_cond_qk => $opt->{logical_cond_qk},
	only_hitcount => $opt->{only_hitcount},
	only_sitesearch => (scalar(@qks) < 1 && defined $opt->{site}) ? 1 : 0,
	qid2rep  => $properties->{qid2rep},
	qid2qtf  => $properties->{qid2qtf},
	qid2gid  => $properties->{qid2gid},
	qid2df   => $properties->{qid2df},
	gid2qids => $properties->{gid2qids},
	dpnd_map => $properties->{dpnd_map},
	antonym_and_negation_expansion => $opt->{antonym_and_negation_expansion},
	option => $opt,
	rawstring => $rawstring,
	result    => $result,
	rep2style => $rep2style,
	s_exp => ((scalar(@sexps) > 1) ? sprintf ("((AND %s ))", join (" ", @sexps)) : sprintf ("( %s )", $sexps[0]))
			});

    print "<!-- " . $ret->{s_exp} . " -->\n" unless ($this->{OPTION}{call_from_api});

    ############
    # ログの取得
    ############

    # パラメータの設定にかかる時間を測定
    $opt->{logger}->setTimeAs('set_params_for_qks', '%.3f') if ($opt->{logger});

    # 検索キーワード生成に関する処理時間をロギング
    if ($opt->{logger}) {
	my %buf = ();
	foreach my $qk (@{$ret->{keywords}}) {
	    foreach my $key ($qk->{logger}->keys) {
		my $value = $qk->{logger}->getParameter($key);
		$buf{$key} += $value;
	    }
	}

	foreach my $key (keys %buf) {
	    $opt->{logger}->setParameterAs($key, sprintf('%.3f', $buf{$key}));
	}
    }

    return $ret;
}

# 削除フラグを設定
sub set_discarded_flag {
    my ($this, $qks) = @_;

    foreach my $qk (@$qks) {
	my %discarded_qids = ();
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /<(形容詞単独)>/ ||
 		    $rep->{fstring} =~ /<(形容動詞単独)>/ ||
 		    $rep->{fstring} =~ /<(NE修飾)>/ ||
		    $rep->{fstring} =~ /<(削除::[^>]+)>/) {
		    $rep->{discarded} = 1;
		    $rep->{reason} .= ($1 . " ");
		    $discarded_qids{$rep->{qid}} = 1;
		}
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		if (exists $discarded_qids{$rep->{kakarimoto_qid}} &&
		    exists $discarded_qids{$rep->{kakarisaki_qid}}) {
		    $rep->{discarded} = 1;
		    $rep->{reason} .= "削除::親子削除済 ";
		}
	    }
	}
    }
}

# 表現文末に削除フラグを設定
sub set_discarded_flag_to_bunmatsu_only {
    my ($this, $qks) = @_;

    foreach my $qk (@$qks) {
	my %discarded_qids = ();
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /<(削除::表現文末)>/) {
		    $rep->{discarded} = 1;
		    $rep->{reason} .= ($1 . " ");
		    $discarded_qids{$rep->{qid}} = 1;
		}
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		if (exists $discarded_qids{$rep->{kakarimoto_qid}} ||
		    exists $discarded_qids{$rep->{kakarisaki_qid}}) {
		    $rep->{discarded} = 1;
		    $rep->{reason} .= "削除::表現文末 ";
		}
	    }
	}
    }
}

sub get_DF {
    my ($this, $term_w_blocktag) = @_;

    # ブロックタイプを考慮していない場合
    unless ($this->{OPTIONS}{use_of_block_types}) {
	my $DFDBs = (index($term_w_blocktag, '->') > 0) ? $this->{DFDBS_DPND} : $this->{DFDBS_WORD};

	return (defined $DFDBs) ? $DFDBs->get($term_w_blocktag) : 0;
    }
    # ブロックタイプを考慮している場合
    else {
	my ($term);
	if ($CONFIG->{IS_NICT_MODE}) { # blocktype is attached backward if NICT
	    ($term) = ($term_w_blocktag =~ /^(.+):..$/);
	}
	else {
	    ($term) = ($term_w_blocktag =~ /^(?:..:)(.+)$/);
	}
	my $df = $this->{CACHED_DF}{$term};
	if ($df) {
	    return $df;
	} else {
	    my $DFDBs = (index($term, '->') > 0) ? $this->{DFDBS_DPND} : $this->{DFDBS_WORD};
	    my $df = $DFDBs->get($term);

	    $this->{CACHED_DF}{$term} = $df;
	    return $df;
	}
    }
}


sub trim {
    my ($this, $query) = @_;

    # 各検索キーワードについて、検索時に必須とする語、除去する語を選定する
    foreach my $qk (@{$query->{keywords}}) {
	# NEタグに基づいて必須を設定
	$this->filter_by_NE($qk, $query);

	# 文末タイプに基づいて削除を設定
	$this->filter_by_bunmatsu_type($qk);

	# 文書頻度の上位・下位の語を削除・必須にする
	$this->filter_by_DF($qk, $query);

	my $discarded_qids = &get_discarded_qids($qk);

	# discarded を除いた後、クエリを構成する語が少ない場合は全て必須にする
	if (scalar(@{$qk->{words}}) - scalar(keys %$discarded_qids) < 4) {
	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@$reps) {
		    next if ($this->{OPTIONS}{syngraph} && !$rep->{isBasicNode});
		    $rep->{requisite} = 1 unless ($rep->{discarded});
		}
	    }
	}

	# gid レベルで必須を設定
	&set_requisite_by_gid($qk);

	# gid レベルで削除を設定
	&set_discarded_by_gid($qk);

	# 係り受けについて削除を設定する
	$discarded_qids = &get_discarded_qids($qk);
	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		my $kakarimoto_qid = $rep->{kakarimoto_qid};
		my $kakarisaki_qid = $rep->{kakarisaki_qid};

		if (exists $discarded_qids->{$kakarimoto_qid} ||
		    exists $discarded_qids->{$kakarisaki_qid}) {
#		    $rep->{discarded} = 1;
		}
	    }
	}
    }
}


sub query_trim {
    my ($this, $keywords) = @_;

    foreach my $qk (@$keywords) {
	my @new_words = ();
	foreach my $reps (@{$qk->{words}}) {
	    my $flag = 1;
	    foreach my $rep (@$reps) {
		next if ($rep->{discarded});

		push(@new_words, []) if ($flag > 0);
		push(@{$new_words[-1]}, $rep);
		$flag = 0;
	    }
	}

	my @new_dpnds = ();
	foreach my $reps (@{$qk->{dpnds}}) {
	    my $flag = 1;
	    foreach my $rep (@$reps) {
		next if ($rep->{discarded});

		push(@new_dpnds, []) if ($flag > 0);
		push(@{$new_dpnds[-1]}, $rep);
		$flag = 0;
	    }
	}

	$qk->{words} = \@new_words;
	$qk->{dpnds} = \@new_dpnds;
    }
}

# 文末タイプに基づいて削除を設定
sub filter_by_bunmatsu_type {
    my ($this, $qk) = @_;

    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    next if ($this->{OPTIONS}{syngraph} && !$rep->{isBasicNode});

	    if ($rep->{question_type}) {
		$rep->{discarded} = 1;
	    }
	}
    }
}

sub set_requisite_by_gid {
    my ($qk, $query) = @_;

    my $gid2req = &get_requisite_gid($qk);
    foreach my $gid (keys %$gid2req) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($gid eq $rep->{gid}) {
		    $rep->{requisite} = 1;
#		    $query->{qid2qtf}{$rep->{qid}} = $BORNUS;
		}
	    }
	}
    }
}

sub set_discarded_by_gid {
    my ($qk) = @_;

    my $gid2dis = &get_discarded_gid($qk);
    foreach my $gid (keys %$gid2dis) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($gid eq $rep->{gid} && !$rep->{requisite} && !$rep->{lexical_head}) {
		    $rep->{discarded} = 1;
		}
	    }
	}
    }
}

sub get_requisite_gid {
    my ($qk) = @_;

    my %buf;
    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    if ($rep->{requisite}) {
		$buf{$rep->{gid}} = 1;
	    }
	}
    }

    return \%buf;
}

sub get_discarded_gid {
    my ($qk) = @_;

    my %buf;
    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    if ($rep->{discarded}) {
		$buf{$rep->{gid}} = 1;
	    }
	}
    }

    return \%buf;
}

sub get_discarded_qids {
    my ($qk) = @_;

    my %buf;
    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    if ($rep->{discarded}) {
		$buf{$rep->{qid}} = 1;
	    }
	}
    }

    return \%buf;
}

# デストラクタ
sub DESTROY {
    my ($this) = @_;

    foreach my $type ('DFDBS_WORD', 'DFDBS_DPND') {
	foreach my $cdb (@{$this->{$type}}) {
	    untie %$cdb;
	}
    }
}

1;
