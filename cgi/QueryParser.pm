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


my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class, $opts) = @_;

    print "constructing QueryParser object...\n" if ($opts->{debug});

    # デフォルト値以外のパラメータが指定されている場合は、新たにKNPをnewする
    if ($opts->{KNP_COMMAND} || $opts->{JUMAN_COMMAND} || $opts->{JUMAN_RCFILE} || $opts->{KNP_RCFILE} ||
	$opts->{KNP_OPTIONS} || $opts->{use_of_case_analysis} || $opts->{use_of_NE_tagger}) {

	$opts->{KNP_COMMAND} = $CONFIG->{KNP_COMMAND} unless ($opts->{KNP_COMMAND});
	$opts->{JUMAN_COMMAND} = $CONFIG->{JUMAN_COMMAND} unless ($opts->{JUMAN_COMMAND});
	$opts->{JUMAN_RCFILE} = $CONFIG->{JUMAN_RCFILE} unless ($opts->{JUMAN_RCFILE});
	$opts->{KNP_RCFILE} = $CONFIG->{KNP_RCFILE} unless ($opts->{KNP_RCFILE});
	$opts->{KNP_OPTIONS} = $CONFIG->{KNP_OPTIONS} unless ($opts->{KNP_OPTIONS});

	# クエリを格解析する
	if ($opts->{use_of_case_analysis}) {
	    @{$opts->{KNP_OPTIONS}} = grep {$_ ne '-dpnd'} @{$opts->{KNP_OPTIONS}};
	}

	# クエリに対して固有表現解析する際は、オプションを追加
	if ($opts->{use_of_NE_tagger}) {
	    push(@{$opts->{KNP_OPTIONS}}, '-ne-crf');
	}

	if ($opts->{debug}) {
	    print "* jmn -> $opts->{JUMAN_COMMAND}\n";
	    print "* knp -> $opts->{KNP_COMMAND}\n";
	    print "* knprcflie -> $opts->{KNP_RCFILE}\n";
	    print "* knpoption -> ", join(",", @{$opts->{KNP_OPTIONS}}) . "\n\n";

	    print "* re-create knp object...";
	}

	$CONFIG->{KNP} = new KNP(-Command => $opts->{KNP_COMMAND},
				 -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
				 -Rcfile => $opts->{KNP_RCFILE},
				 -JumanRcfile => $opts->{JUMAN_RCFILE},
				 -JumanCommand => $opts->{JUMAN_COMMAND});

	print " done.\n" if ($opts->{debug});
    }

    my $this = {
	KNP => $CONFIG->{KNP},
	OPTIONS => {trimming => $opts->{QUERY_TRIMMING},
		    jyushi => (),
		    keishi => (),
		    syngraph => undef}
    };

#    $this->{OPTIONS}{jyushi} = $opts->{JYUSHI} if ($opts->{JYUSHI});
#    $this->{OPTIONS}{keishi} = $opts->{KEISHI} if ($opts->{KEISHI});


#   my ($dfdbs_w, $dfdbs_d) = &load_DFDBs($opts->{DFDB_DIR}, $opts);
#   $this->{DFDBS_WORD} = $dfdbs_w;
#   $this->{DFDBS_DPND} = $dfdbs_d;
    $this->{DFDBS_WORD} = new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $opts->{DFDB_DIR})) if (-e $opts->{DFDB_DIR});
    $this->{DFDBS_DPND} = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $opts->{DFDB_DIR})) if (-e $opts->{DFDB_DIR});


    # ストップワードの処理
    unless ($opts->{STOP_WORDS}) {
	$this->{INDEXER} = new Indexer({ignore_yomi => $opts->{ignore_yomi}});
	$this->{INDEXER_GENKEI} = new Indexer({ignore_yomi => $opts->{ignore_yomi}, genkei => 1});
    } else {
	my %stop_words;
	foreach my $word (@{$opts->{STOP_WORDS}}) {
	    # 代表表記ではない場合、代表表記を得る
	    unless ($word =~ /\//) {
		my $result = $this->{KNP}->parse($word);

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
	$this->{INDEXER} = new Indexer({ STOP_WORDS => \%stop_words,
					 ignore_yomi => $opts->{ignore_yomi} });
	$this->{INDEXER_GENKEI} = new Indexer({ STOP_WORDS => \%stop_words,
						ignore_yomi => $opts->{ignore_yomi},
					        genkei => 1 });
    }

    print "QueryParser object construction is OK.\n\n" if ($opts->{debug});
    bless $this;
}

# 検索クエリを解析
sub parse {
    my ($this, $qks_str, $opt) = @_;

    $this->{OPTIONS}{syngraph} = $opt->{syngraph};

    my @qks = ();
    my %wbuff = ();
    my %dbuff = ();
    # 必要であればSynGraphをnewし、メンバ変数として保持する
    if ($opt->{syngraph}) {
	if ($opt->{SYNGRAPH}) {
	    $this->{SYNGRAPH} = $opt->{SYNGRAPH};
	} else {
	    my $CONFIG = Configure::get_instance();
	    push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});
	    require SynGraph;

	    $this->{SYNGRAPH} = new SynGraph($CONFIG->{SYNDB_PATH});
	}
	$this->{SYNGRAPH_OPTION} = {regist_exclude_semi_contentword => 1, relation => 1, antonym => 1, hypocut_attachnode => 9};
    }
    # SYNGRAPHをnewする
    $opt->{logger}->setTimeAs('new_syngraph', '%.3f') if ($opt->{logger});


    ## 空白で区切る
    # $qks_str =~ s/ /　/g;
    my $indexer = $this->{INDEXER};
    my $delim = ($opt->{no_use_of_Zwhitespace_as_delimiter}) ? "(?: )" : "(?: |　)+";
    foreach my $q_str (split(/$delim/, $qks_str)) {
	# 空文字はスキップ
	next if ($q_str eq '');

	my $near = $opt->{near};
	my $logical_cond_qkw = 'AND'; # 検索語に含まれる単語間の論理条件
	my $keep_order = 1;
	my $force_dpnd = $opt->{force_dpnd};
	my $sentence_flag = -1;
	my $phrasal_flag = -1;

	# フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/) {
	    $phrasal_flag = 1;
	    $q_str = $1;
	    $near = 1;
	    $indexer = $this->{INDEXER_GENKEI} if ($CONFIG->{IS_NICT_MODE});
	    # フレーズ検索ではSynNodeを利用しない
	    $opt->{disable_synnode} = 1;
	}
	# 近接検索かどうかの判定
	elsif ($q_str =~ /^(.+)?~(.+)$/) {
	    $q_str = $1;
	    # 検索制約の取得
	    my $constraint_tag = $2;

	    # 近接制約
	    if ($constraint_tag =~ /^(\d+)(W|S)$/i) {
		$logical_cond_qkw = 'AND';
		$near = $1;
		$sentence_flag = 1 if ($2 =~ /S/i);
		$keep_order = 0 if ($2 eq 's' || $2 eq 'w');
	    }
	    # 論理条件制約
	    elsif ($constraint_tag =~ /(AND|OR)/) {
		$logical_cond_qkw = $1;
	    }
	    # 係り受け強制制約
	    elsif ($constraint_tag =~ /FD/) {
		$logical_cond_qkw = 'AND';
		$force_dpnd = 1;
	    }
	}
	# サイト指定検索かどうかの判定
	elsif ($q_str =~ /^site:(.+)$/) {
	    $opt->{site} = $1;
	    next;
	}
	# 指定なし
	else {
	    # クエリに制約(近接およびフレーズ)が指定されていなければ~100wをつける
	    $logical_cond_qkw = 'AND';
	    $near = 100;
	    $sentence_flag = 0;
	    $keep_order = 0;
	}

	## 半角アスキー文字列を全角に置換する
	$q_str = Unicode::Japanese->new($q_str)->h2z->getu;

	$q_str =~ s/－/−/g; # FULLWIDTH HYPHEN-MINUS (U+ff0d) -> MINUS SIGN (U+2212)
	$q_str =~ s/～/〜/g; # FULLWIDTH TILDE (U+ff5e) -> WAVE DASH (U+301c)
	$q_str =~ s/∥/‖/g; # PARALLEL TO (U+2225) -> DOUBLE VERTICAL LINE (U+2016)
	$q_str =~ s/￠/¢/g;  # FULLWIDTH CENT SIGN (U+ffe0) -> CENT SIGN (U+00a2)
	$q_str =~ s/￡/£/g;  # FULLWIDTH POUND SIGN (U+ffe1) -> POUND SIGN (U+00a3)
	$q_str =~ s/￢/¬/g;  # FULLWIDTH NOT SIGN (U+ffe2) -> NOT SIGN (U+00ac)
	$q_str =~ s/—/―/g; # EM DASH (U+2014) -> HORIZONTAL BAR (U+2015)
	$q_str =~ s/¥/￥/g;  # YEN SIGN (U+00a5) -> FULLWIDTH YEN SIGN (U+ffe5)

	my $q;
	if ($opt->{syngraph} > 0) {
	    $q = new QueryKeyword(
		$q_str,
		$sentence_flag,
		$phrasal_flag,
		$near,
		$keep_order,
		$force_dpnd,
		$logical_cond_qkw,
		$opt->{syngraph},
		{ knp => $this->{KNP},
		  indexer => $indexer,
		  syngraph => $this->{SYNGRAPH},
		  syngraph_option => $this->{SYNGRAPH_OPTION},
		  requisite_item_detector => $this->{requisite_item_detector},
		  query_filter => $this->{query_filter},
		  trimming => $opt->{trimming},
		  antonym_and_negation_expansion => $opt->{antonym_and_negation_expansion},
		  disable_dpnd => $opt->{disable_dpnd},
		  disable_synnode => $opt->{disable_synnode},
		  end_of_sentence_process => $opt->{end_of_sentence_process},
		  telic_process => $opt->{telic_process},
		  CN_process => $opt->{CN_process},
		  NE_process => $opt->{NE_process},
		  modifier_of_NE_process => $opt->{modifier_of_NE_process},
		  debug => $opt->{debug}
		});
	} else {
	    $q = new QueryKeyword(
		$q_str,
		$sentence_flag,
		$phrasal_flag,
		$near,
		$keep_order,
		$force_dpnd,
		$logical_cond_qkw,
		$opt->{syngraph},
		{ knp => $this->{KNP},
		  indexer => $indexer,
		  requisite_item_detector => $this->{requisite_item_detector},
		  query_filter => $opt->{query_filter},
		  trimming => $opt->{trimming},
		  end_of_sentence_process => $opt->{end_of_sentence_process},
		  telic_process => $opt->{telic_process},
		  CN_process => $opt->{CN_process},
		  NE_process => $opt->{NE_process},
		  modifier_of_NE_process => $opt->{modifier_of_NE_process},
		  debug => $opt->{debug}
		});
	}
	if ($CONFIG->{FORCE_APPROXIMATE_BTW_EXPRESSIONS} && scalar(@qks) > 0) {
  	    push (@{$qks[0]->{words}}, @{$q->{words}}) if (scalar(@{$q->{words}}) > 0);
  	    push (@{$qks[0]->{dpnds}}, @{$q->{dpnds}}) if (scalar(@{$q->{dpnds}}) > 0);
  	    $qks[0]->{rawstring} .= (" " . $q->{rawstring});
  	} else {
	    push(@qks, $q);
  	}
    }
    # QueryKeyword作成にかかる時間を測定
    $opt->{logger}->setTimeAs('make_qks', '%.3f') if ($opt->{logger});


    # $gid をふり直す
    foreach my $qk (@qks) {
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
		my ($saki, $moto) = ($rep->{string} =~ /^(.+?)\-\>(.+?)$/);
		my $saki_gid = $str2gid{$saki};
		my $moto_gid = $str2gid{$moto};
		$rep->{gid} = sprintf ("%d/%d", $saki_gid, $moto_gid);
	    }
	}
    }

    my $qid = 0;
    my %qid2rep = ();
    my %rep2qid = ();
    my %rep2gid = ();
    my %qid2gid = ();
    my %gid2qids = ();
    my %qid2df = ();
    my %dpnd_map = ();
    my %gid2df = ();
    my %qid2qtf = ();

    my %styleBuf;
    my $count = 0;

    # 検索語中の各索引語にIDをふる
    my $gid_prefix = 0;
    for (my $gid_prefix = 0; $gid_prefix < scalar(@qks); $gid_prefix++) {
	my $qk = $qks[$gid_prefix];
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		# グループIDを検索キーワード毎に異なるようにする
		$rep->{gid} = "$gid_prefix.$rep->{gid}";

		$rep2qid{$rep->{string}} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid2gid{$qid} = $rep->{gid};
		$rep2gid{$rep->{string}} = $rep->{gid};
		push(@{$gid2qids{$rep->{gid}}}, $qid);
		$qid2df{$qid} = $this->get_DF($rep->{string});
		$qid2qtf{$qid} = $rep->{freq};

		$rep->{qid} = $qid;
		$rep->{df} = $qid2df{$qid};
		$rep->{gdf} = $qid2df{$qid};

		if ($rep->{isBasicNode}) {
		    $gid2df{$rep->{gid}} = $rep->{df};
		}
		$qid++;
		print $rep->{string} . " " . $rep->{qid} . " " . $rep->{gid} . " " . $rep->{df} . "<br>\n" if ($opt->{verbose});

		# スニペットでハイライト表示する際のスタイルを設定

		next if ($qk->{is_phrasal_search} > 0);

		if (exists $styleBuf{$rep->{string}}) {
		    $rep->{stylesheet} = $styleBuf{$rep->{string}};
		} else {
		    my $foreground = ($count > 4) ? 'white' : 'black';
		    my $background = $CONFIG->{HIGHLIGHT_COLOR}[$count];
		    $rep->{stylesheet} = sprintf "background-color: %s; color: %s; margin:0.1em 0.25em;", $background, $foreground;
		    $styleBuf{$rep->{string}} = $rep->{stylesheet};
		}
	    }
	    $count = (++$count % scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		# グループIDを検索キーワード毎に異なるようにする
		my ($x, $y) = split("/", $rep->{gid});
		$rep->{gid} = "$gid_prefix.$x/$gid_prefix.$y";

		$qid2rep{$qid} = $rep->{string};
		$qid2gid{$qid} = $rep->{gid};
		$qid2df{$qid} = $this->get_DF($rep->{string});
		$qid2qtf{$qid} = $rep->{freq};

		$rep->{qid} = $qid;
		$rep->{gdf} = $qid2df{$qid};
		$rep->{df} = $qid2df{$qid};

		push(@{$gid2qids{$rep->{gid}}}, $qid);

		my ($kakarimoto, $kakarisaki) = split('->', $rep->{string});
		my $kakarimoto_qid = $rep2qid{$kakarimoto};
		my $kakarisaki_qid = $rep2qid{$kakarisaki};
		$rep->{kakarimoto_qid} = $kakarimoto_qid;
		$rep->{kakarisaki_qid} = $kakarisaki_qid;
		$rep->{kakarimoto_gid} = $rep2gid{$kakarimoto};
		$rep->{kakarisaki_gid} = $rep2gid{$kakarisaki};
		push(@{$dpnd_map{$rep2qid{$kakarimoto}}}, {kakarisaki_qid => $kakarisaki_qid, dpnd_qid => $qid});

		if ($rep->{isBasicNode}) {
		    $gid2df{$rep->{gid}} = $rep->{df};
		}
		$qid++;
	    }
	}
    }

#   $opt->{logger}->clearTimer();

    if ($CONFIG->{MAX_NUMBER_OF_SYNNODES}) {
	foreach my $qk (@qks) {
	    $qk->reduceSynnodes($opt->{antonym_and_negation_expansion});
	}
    }

    # SynNodeのgdfは基本ノードのgdfにする
    if ($opt->{syngraph}) {
	foreach my $qid (keys %qid2gid) {
	    my $gid = $qid2gid{$qid};
	    my $df_of_basic_node = $gid2df{$gid};
	    $df_of_basic_node = 0 unless (defined $df_of_basic_node);
	    $qid2df{$qid} = $df_of_basic_node;
	    print "qid=$qid gid=$gid df=$df_of_basic_node<br>\n" if ($opt->{verbose});
	}
    }

    # 検索クエリを表す構造体
    my $ret = new Query({ keywords => \@qks,
			  logical_cond_qk => $opt->{logical_cond_qk},
			  only_hitcount => $opt->{only_hitcount},
			  only_sitesearch => (scalar(@qks) < 1 && defined $opt->{site}) ? 1 : 0,
			  qid2rep => \%qid2rep,
			  qid2qtf => \%qid2qtf,
			  qid2gid => \%qid2gid,
			  qid2df => \%qid2df,
			  gid2qids => \%gid2qids,
			  dpnd_map => \%dpnd_map,
			  antonym_and_negation_expansion => $opt->{antonym_and_negation_expansion},
			  option => $opt
			});



    ###########################################
    # 以下はクエリ処理（削除、重み付け）
    ###########################################

    $this->set_discarded_flag_to_bunmatsu_only(\@qks);
    $this->query_trim(\@qks);


    my %gid2weight = ();
    unless ($this->{OPTIONS}{trimming}) {
	foreach my $qk (@qks) {
	    foreach my $type ('words', 'dpnds') {
		foreach my $reps (@{$qk->{$type}}) {
		    foreach my $rep (@{$reps}) {
			my $gid = $rep->{gid};
			$gid2weight{$gid} = 1;
		    }
		}
	    }
	}
    } else {
# 	$this->set_head_flag(\@qks);
# 	$this->set_discarded_flag(\@qks);
#  	$this->set_requisite_flag_for_dpnds_in_NE(\@qks);
#   	$this->change_weight_keishi(\@qks, $this->{OPTIONS}{keishi});
#   	$this->change_weight_jyushi(\@qks, $this->{OPTIONS}{jyushi});

	$this->set_discarded_flag_to_bunmatsu_only(\@qks);

	# 重みの最大は$this->{OPTIONS}{jyushi}
	my %qid2qtf = ();
	foreach my $qk (@qks) {
	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@{$reps}) {
		    my $qid = $rep->{qid};
		    $rep->{weight} = $this->{OPTIONS}{jyushi}{NE} if ($rep->{weight} > $this->{OPTIONS}{jyushi}{NE});
		    $qid2qtf{$qid} = $rep->{freq};
		    $gid2weight{$rep->{gid}} = $rep->{weight} if ($rep->{isBasicNode} || !$opt->{syngraph});
		}
	    }

	    foreach my $reps (@{$qk->{dpnds}}) {
		foreach my $rep (@{$reps}) {
		    my $qid = $rep->{qid};
		    $rep->{weight} = $this->{OPTIONS}{jyushi}{NE} if ($rep->{weight} > $this->{OPTIONS}{jyushi}{NE});
		    $qid2qtf{$qid} = $rep->{freq};
		    $gid2weight{$rep->{gid}} = $rep->{weight} if ($rep->{isBasicNode} || !$opt->{syngraph});
		}
	    }
	}
    
	$ret->{qid2qtf} = \%qid2qtf;
    }
    $ret->{gid2weight} = \%gid2weight;

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
	    # print $key . " " . $buf{$key} . "<BR>\n";
	}
    }

    return $ret;
}

# NE,主辞を必須に設定
sub set_requisite_flag {
    my ($this, $qks) = @_;

    foreach my $qk (@$qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		next if ($rep->{discarded});
		if ($rep->{lexical_head}) {
		    $rep->{requisite} = 1;
		}
		elsif ($rep->{fstring} =~ /<NE:/ && $rep->{string} !~ /^日本$/ && $rep->{string} !~ /^日本\//) {
		    $rep->{NE} = 1;
		    $rep->{requisite} = 1;
		}
	    }
	}
    }
}

# NE内の係り受けを必須に設定
sub set_requisite_flag_for_dpnds_in_NE {
    my ($this, $qks) = @_;

    my $NE_id = 0;
    my %qids_in_NEs = ();
    foreach my $qk (@$qks) {
	foreach my $reps (@{$qk->{words}}) {
	    if ($reps->[0]{NE}) {
		foreach my $rep (@$reps) {
		    $qids_in_NEs{$rep->{qid}} = $NE_id;
		}
	    } else {
		$NE_id++;
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		if (exists $qids_in_NEs{$rep->{kakarimoto_qid}} &&
		    exists $qids_in_NEs{$rep->{kakarisaki_qid}}) {
		    if ($qids_in_NEs{$rep->{kakarimoto_qid}} ==  $qids_in_NEs{$rep->{kakarisaki_qid}}) {
			$rep->{requisite} = 1;
			$rep->{reason} .= "NE内係り受け ";
		    }
		}
	    }
	}
    }
}

# 複合名詞内の係り受けを重要視する
sub set_weight_for_dpnds_in_CN {
    my ($this, $qks, $weight) = @_;

    my $CN_id = 0;
    my %qids_in_CNs = ();
    foreach my $qk (@$qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /<複合.>/) {
		    $qids_in_CNs{$rep->{qid}} = $CN_id;
		} else {
		    $CN_id++;
		}
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		if (exists $qids_in_CNs{$rep->{kakarimoto_qid}} &&
		    exists $qids_in_CNs{$rep->{kakarisaki_qid}}) {
		    if ($qids_in_CNs{$rep->{kakarimoto_qid}} ==  $qids_in_CNs{$rep->{kakarisaki_qid}}) {
			$rep->{weight} *= $weight->{CN};
			$rep->{weight_changed} = 1;
			$rep->{reason} .= "CN内係り受け ($weight->{CN}) ";
		    }
		}
	    }
	}
    }
}

# NEを別クエリとする
sub create_new_query_from_NE {
    my ($this, $qks) = @_;

    my @NEs = ();
    foreach my $qk (@$qks) {
	push(@NEs, '');	
	foreach my $reps (@{$qk->{words}}) {
	    if ($reps->[0]{NE}) {
		my $string = $reps->[0]{string};
		$string =~ s/\/.+$//;
		$NEs[-1] .= $string;
		foreach my $rep (@$reps) {
		    $rep->{discarded} = 1;
		    $rep->{reason} .= "削除::別クエリ ";
		}
	    } else {
		if ($NEs[-1] ne '') {
		    $NEs[-1] = "\"" . $NEs[-1] . "\"";
		    push(@NEs, '');
		}
	    }
	}
    }

    my $new_query = join('　', @NEs);
    $this->{OPTIONS}{trimming} = undef;
    my $new_q = $this->parse($new_query);
    return $new_q;
}

# 主辞を設定
sub set_head_flag {
    my ($this, $qks) = @_;

    foreach my $qk (@$qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /<クエリ主辞>/) {
		    $rep->{lexical_head} = 1;
		}
	    }
	}
    }
}

# 重みを変更（重視）
sub change_weight_jyushi {
    my ($this, $qks, $weight) = @_;

    $this->set_weight_for_dpnds_in_CN($qks, $weight);

    foreach my $qk (@$qks) {
	my %discarded_qids = ();
	my %weighted_qids = ();
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /<(NE):/ && $rep->{string} !~ /^日本$/ && $rep->{string} !~ /^日本\//) {
		    $rep->{weight} *= ($weight->{NE});
		    $rep->{weight_changed} = 1;
		    $rep->{reason} .= "$1 ($weight->{NE}) ";
		    $weighted_qids{NE}->{$rep->{qid}} = 1;
		}
		elsif ($rep->{lexical_head}) {
		    $rep->{weight} *= ($weight->{HEAD});
		    $rep->{weight_changed} = 1;
		    $rep->{reason} .= "クエリ主辞 ($weight->{HEAD}) ";
		    $weighted_qids{HEAD}->{$rep->{qid}} = 1;
		}
	    }
	}

	foreach my $T (keys %weighted_qids) {
	    foreach my $reps (@{$qk->{dpnds}}) {
		foreach my $rep (@$reps) {
		    if (exists $weighted_qids{$T}->{$rep->{kakarimoto_qid}} &&
			exists $weighted_qids{$T}->{$rep->{kakarisaki_qid}}) {
			$rep->{weight} *= ($weight->{$T});
			$rep->{weight_changed} = 1;
			$rep->{reason} .= "親子Ｗ変更 ($weight->{$T})) ";
		    }
		}
	    }
	}
    }
}

# 重みを変更（軽視）
sub change_weight_keishi {
    my ($this, $qks, $weight) = @_;

    my %weighted_qids = ();
    foreach my $qk (@$qks) {
	my %discarded_qids = ();
	foreach my $reps (@{$qk->{words}}) {

	    foreach my $rep (@$reps) {
		if ($rep->{fstring} =~ /(<NE修飾>)/) {
		    $rep->{weight} *= ($weight->{NE_MOD});
		    $rep->{weight_changed} = 1;
		    $rep->{reason} .= "$1 ($weight->{NE_MOD}) ";
		    $weighted_qids{$rep->{qid}} = 1;
		}
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@$reps) {
		if (exists $weighted_qids{$rep->{kakarimoto_qid}} &&
		    exists $weighted_qids{$rep->{kakarisaki_qid}}) {
		    $rep->{weight} *= ($weight->{NE_MOD});
		    $rep->{weight_changed} = 1;
		    $rep->{reason} .= "親子Ｗ変更 ($weight->{NE_MOD}) ";
		}
	    }
	}
    }
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


sub load_DFDBs {
    my ($dbdir, $opts) = @_;

    print "* loading word dfdbs from $opts->{DFDB_DIR}" if ($opts->{debug});

    my @DF_WORD_DBs = ();
    my @DF_DPND_DBs = ();

    if (defined $dbdir) {
	opendir(DIR, $dbdir) or die "$! ($dbdir)\n";
	foreach my $cdbf (readdir(DIR)) {
	    next unless ($cdbf =~ /cdb(.\d+)?$/);

	    my $fp = "$dbdir/$cdbf";
	    tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	    if (index($cdbf, 'dpnd') > -1) {
		push(@DF_DPND_DBs, \%dfdb);
	    } elsif (index($cdbf, 'word') > -1) {
		push(@DF_WORD_DBs, \%dfdb);
	    }
	}
	closedir(DIR);
    }
    print " is done\n" if ($opts->{debug});

    return (\@DF_WORD_DBs, \@DF_DPND_DBs);
}

sub get_DF {
    my ($this, $k) = @_;

    my $k_utf8 = encode('utf8', $k);
    my $DFDBs = (index($k, '->') > 0) ? $this->{DFDBS_DPND} : $this->{DFDBS_WORD};

    return (defined $DFDBs) ? $DFDBs->get($k_utf8) : 0;
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


# 文書頻度の上位・下位の語を削除・必須にする
sub filter_by_DF {
    my ($this, $qk, $query) = @_;
    my $qid2df = $query->{qid2df};

    # 単語について文書頻度を獲得
    my %qid2df_word = ();
    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    # SynGraph 検索の場合は基本ノードだけ
	    next if ($this->{OPTIONS}{syngraph} && !$rep->{isBasicNode});

	    my $qid = $rep->{qid};
	    $qid2df_word{$qid} = $qid2df->{$qid};
	}
    }

    my $rank = 1;
    my %qid2rank = ();
    foreach my $qid (sort {$qid2df_word{$a} <=> $qid2df_word{$b}} keys %qid2df_word) {
	$qid2rank{$qid} = $rank++;
    }

    my $num_of_word = $rank - 1;
    my $N = int(0.2 * $num_of_word + 0.5);
    $N = 1 if ($N < 1);

    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    # SynGraph 検索の場合は基本ノードだけが対象
	    # Syn ノードは後で gid を見て削除
	    next if ($this->{OPTIONS}{syngraph} && !$rep->{isBasicNode});

	    my $qid = $rep->{qid};
	    $rep->{df_rank} = $qid2rank{$qid};

	    # 文書頻度の低い語は必須
	    if ($qid2rank{$qid} < $N + 1) {
		$rep->{requisite} = 1;
#		$query->{qid2qtf}{$qid} = $BORNUS;
	    }
	    # 文書頻度の高い語は削除
	    elsif ($qid2rank{$qid} > $num_of_word - $N) {
		$rep->{discarded} = 1 if (!$rep->{requisite} && !$rep->{lexical_head});
	    }
	}
    }
}

# NEタグに基づいて必須を設定
sub filter_by_NE {
    my ($this, $qk, $query) = @_;

    foreach my $reps (@{$qk->{words}}) {
	foreach my $rep (@$reps) {
	    next if ($this->{OPTIONS}{syngraph} && !$rep->{isBasicNode});

	    if ($rep->{NE} && $rep->{string} !~ /^日本$/ && $rep->{string} !~ /^日本\//) {
		$rep->{requisite} = 1;
#		$query->{qid2qtf}{$rep->{qid}} = $BORNUS;
	    }
	}
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
