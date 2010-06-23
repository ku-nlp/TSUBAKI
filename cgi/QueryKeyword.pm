package QueryKeyword;

#$Id$

# 1つの検索語を表すクラス

use strict;
use utf8;
use Encode;
use Data::Dumper;
use Configure;
use Error qw(:try);
use KNP::Result;
use Logger;


my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class, $search_expression, $sentence_flag, $is_phrasal_search, $near, $keep_order, $force_dpnd, $logical_cond_qkw, $opt) = @_;

    my $this = {
	words => [],
	dpnds => [],
	sentence_flag => $sentence_flag,
	is_phrasal_search => $is_phrasal_search,
	near => $near,
	keep_order => $keep_order,
	force_dpnd => $force_dpnd,
	logical_cond_qkw => $logical_cond_qkw,
	rawstring => $search_expression,
	syngraph => $opt->{syngraph},
	disable_dpnd => $opt->{disable_dpnd},
	disable_synnode => $opt->{disable_synnode},
	logger => new Logger(0)
    };
    bless $this;

    # 言語解析
    my $result = $this->_linguisticAnalysis($search_expression, $opt);

    # タームの抽出
    my $terms = $this->_extractTerms($opt->{indexer}, $result, $opt);

    # タームの抽出
    $this->_setTerms($terms, $opt);

    # ログを取る
    $this->{logger}->setTimeAs('create_query', '%.3f');


    return $this;
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
    try {
	$knpresult = $CONFIG->{KNP}->parse($search_expression);
    }
    catch Error with {
	my $err = shift;
	print "Bad query: $search_expression<BR>\n";
	print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
	print "Dumpping messages of KNP object is following.<BR>\n";
	print Dumper($opt->{knp}) . "<BR>\n";
	exit(1);
    };
    $this->{logger}->setTimeAs('KNP', '%.3f');

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
    $opt->{syngraph_option}{antonym} = 1;
    $opt->{syngraph_option}{force_match}{fuzoku} = 1;

    $knpresult->set_id(0);
    my $synresult = $CONFIG->{SYNGRAPH}->OutputSynFormat($knpresult, $opt->{syngraph_option}, $opt->{syngraph_option});

    $this->{syn_result} = new KNP::Result($synresult);
    $this->{logger}->setTimeAs('SynGraph', '%.3f');

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
    $this->{logger}->setTimeAs('QueryAnalyzer', '%.3f');

    $this->{knp_result} = $knpresult;
}

# タームの抽出
sub _extractTerms {
    my ($this, $indexer, $result, $opt) = @_;

    my $terms;
    # WebClusteringではKNPの解析結果からtermを抜き出していることに注意
    if ($opt->{english}) {
	$terms = $indexer->makeIndexFromCONLLData();
    }
    elsif ($opt->{syngraph}) {
	$terms = $indexer->makeIndexFromSynGraphResultObject(
	    $result,
	    {
		use_of_syngraph_dependency => $CONFIG->{USE_OF_SYNGRAPH_DEPENDENCY},
		use_of_hypernym => $CONFIG->{USE_OF_HYPERNYM},
		disable_synnode => $opt->{disable_synnode},
		force_dpnd => $this->{force_dpnd},
		string_mode => 0,
		use_of_negation_and_antonym => $CONFIG->{USE_OF_NEGATION_AND_ANTONYM},
		antonym_and_negation_expansion => $opt->{antonym_and_negation_expansion}
	    });
    }
    else {
	# KNP 結果から索引語を抽出
	$terms = $indexer->makeIndexFromKNPResult($result->all);
    }

    $this->{logger}->setTimeAs('Indexer', '%.3f');

    # Indexer.pm より返される索引語を同じ代表表記・SYNノードごとにまとめる
    my %buf;
    foreach my $term (@$terms) {
	$buf{$term->{group_id}} = [] unless (exists($buf{$term->{group_id}}));
	push(@{$buf{$term->{group_id}}}, $term);
    }

    return \%buf;
}

# タームの保存
sub _setTerms {
    my ($this, $terms, $opt) = @_;

    my $num_of_semi_content_words = 0;
    foreach my $group_id (sort {$terms->{$a}[0]{pos} <=> $terms->{$b}[0]{pos}} keys %$terms) {
	my @word_reps;
	my @dpnd_reps;

	my $flag = 0;
	foreach my $term (@{$terms->{$group_id}}) {
	    # 近接条件が指定されていない かつ 機能語 の場合は検索に用いない
	    next if ($term->{isContentWord} < 1 && $this->{is_phrasal_search} < 0);

	    # OR 検索が指定されていた場合の処理
	    if ($this->{logical_cond_qkw} eq 'OR') {
		$term->{requisite} = 0;
		$term->{optional} = 1;
	    }

	    # ブロックタイプを考慮する場合
	    if ($opt->{blockTypes} && %{$opt->{blockTypes}}) {
		foreach my $blockType (keys %{$opt->{blockTypes}}) {
		    &push_string_to_reps(\@dpnd_reps, \@word_reps, $term, sprintf ("%s%s", $blockType, $term->{midasi}), $group_id, $opt);
		}
	    }
	    else {
		&push_string_to_reps(\@dpnd_reps, \@word_reps, $term, $term->{midasi}, $group_id, $opt);
	    }

	    if ($term->{midasi} !~ /\-\>/) {
		$flag = 1 if ($term->{midasi} =~ /\+/ && $term->{isBasicNode});
		last if ($term->{midasi} =~ /\+/ && $term->{isBasicNode} && $this->{is_phrasal_search} > 0);
	    }
	}
	$num_of_semi_content_words++ if ($flag);

	push(@{$this->{words}}, \@word_reps) if (scalar(@word_reps) > 0);
	push(@{$this->{dpnds}}, \@dpnd_reps) if (scalar(@dpnd_reps) > 0);
    }

    if ($this->{is_phrasal_search} > 0) {
	$this->{near} = scalar(@{$this->{words}}) + $num_of_semi_content_words;
    }
}

# @dpnd_reps, \@word_repsに追加する関数
sub push_string_to_reps {
    my ($dpnd_reps_ar, $word_reps_ar, $m, $regist_string, $group_id, $opt) = @_;

    my @midasis = ();
    push (@midasis, $regist_string);
    if ($m->{midasi} =~ /\-\>/) {
	if ($opt->{use_of_anaphora_resolution}) {
	    $regist_string =~ s/\-/=/;
	    push (@midasis, $regist_string);
	}

	foreach my $midasi (@midasis) {
	    push(@{$dpnd_reps_ar}, {
		string => $midasi,
		gid => $group_id,
		qid => -1,
		weight => 1,
		freq => $m->{freq},
		requisite => $m->{requisite},
		optional => $m->{optional},
		isContentWord => $m->{isContentWord},
		isBasicNode => $m->{isBasicNode},
		isAdditionalNode => ($m->{additional_node}) ? 1 : 0
		});
	}
    }
    else {
	push (@midasis, sprintf ("%s<上位語>", $regist_string)) if ($opt->{use_of_hyponym});
	foreach my $midasi (@midasis) {

	    push(@{$word_reps_ar},
		 {
		     surf => $m->{surf},
		     string => $midasi,
		     midasi_with_yomi => $m->{midasi_with_yomi},
		     gid => $group_id,
		     qid => -1,
		     weight => 1,
		     freq => $m->{freq},
		     requisite => $m->{requisite},
		     optional =>  $m->{optional},
		     isContentWord => $m->{isContentWord},
		     question_type => $m->{question_type},
		     NE => $m->{NE},
		     isBasicNode => $m->{isBasicNode},
		     fstring => $m->{fstring},
		     isAdditionalNode => ($m->{additional_node}) ? 1 : 0,
		     katsuyou => $m->{katsuyou},
		     POS => $m->{POS}
		 });
	}
    }
}

# SynNodeを減らす
sub reduceSynnodes {
   my ($this, $use_of_antonym_expansion) = @_;

   my $N = ($use_of_antonym_expansion) ? int (0.5 * ($CONFIG->{MAX_NUMBER_OF_SYNNODES} + 1)) : $CONFIG->{MAX_NUMBER_OF_SYNNODES};
   my @new_words;
   foreach my $words (@{$this->{words}}) {
       if (scalar(@$words) < $N) {
	   push (@new_words, $words);
       } else {
	   # もともとの語とクエリ処理により追加された語を分別
	   my @basic_nodes;
	   my @original_words;
	   my @appended_words;
	   foreach my $word (sort {$b->{gdf} <=> $a->{gdf}} @$words) {
	       if ($word->{isAdditionalNode}) {
		   push (@appended_words, $word) if (scalar(@appended_words) < $N);
	       } else {
		   if ($word->{isBasicNode}) {
		       push (@basic_nodes, $word);
		   } else {
		       push (@original_words, $word) if (scalar(@original_words) < $N);
		   }
	       }
	   }

	   push (@new_words, \@basic_nodes);
	   push (@{$new_words[-1]}, @original_words);
	   push (@{$new_words[-1]}, @appended_words);
       }
   }

   $this->{words} = \@new_words;
}

# ブラウザ出力用
sub print_for_web {
    my ($this) = @_;

    print qq(<H4 style="background-color:black; color: white;"><A name="knp">KNP解析結果(TREE)</A></H4>\n);
    print qq(<PRE class="knp_tree">\n);
    $this->{knp_result}->draw_tag_tree(<STDOUT>);
    print qq(</PRE>\n\n);


    print qq(<H4 style="background-color:black; color: white;">KNP解析結果(TAB)</H4>\n);
    print qq(<PRE class="knp_tab">\n);
    print $this->{knp_result}->all_dynamic . "\n";
    print qq(</PRE>\n\n);

    if ($this->{syn_result}) {
	print qq(<H4 style="background-color:black; color: white;"><A name="syngraph">SYNGRAPH解析結果</A></H4>\n);
	my $ret = $this->{syn_result}->all_dynamic();
	$ret = decode('utf8', $ret) unless (utf8::is_utf8($ret));
	$ret =~ s/</&lt;/g;
	print qq(<PRE class="syn">\n);
	print $ret . "\n";
	print qq(</PRE>\n\n);
    }


    my $count = 0;
    my @colors = ('white', '#efefef');

    printf(qq(<H4 style="background-color:black; color: white;"><A name="query">クエリの解析結果</A></H4>\n));
    print qq(<TABLE border="1" width="100%">\n);
    my $syngraph = Configure::getSynGraphObj();
    foreach my $T ('words', 'dpnds') {
	foreach my $reps (@{$this->{$T}}) {
	    my $flag = ($reps->[0]{requisite}) ? '<FONT color="red">必</FONT>' : (($reps->[0]{optional}) ? '<FONT color="blue">オ</FONT>' : '?');
	    my $size = scalar(@$reps);

	    my $first = 1;
	    foreach my $rep (@$reps) {
		my $gid = $rep->{gid};
		my $qid = $rep->{qid};
		my $gdf = $rep->{gdf};
		my $qtf = $rep->{qtf};
		my $str = $rep->{string};
		my $str_w_yomi = $rep->{midasi_with_yomi};

		if ($flag) {
		    my $NE = ($rep->{NE}) ? $rep->{NE} : '--';
		    $NE =~ s/</&lt;/g;
		    printf qq(<TR bgcolor="%s">), $colors[++$count % 2];
		    printf qq(<TD align="center" rowspan="$size">%s</TD>), $flag;
		    printf qq(<TD align="center" rowspan="$size">%s</TD>), $NE;
		    $flag = 0;
		} else {
		    printf qq(<TR bgcolor="%s">), $colors[$count % 2];
		}

		if ($this->{syn_result}) {
		    my @synonymous_exps = split(/\|+/, decode('utf8', $syngraph->{syndb}{$str_w_yomi}));
		    unshift (@synonymous_exps, '<BR>') if (scalar(@synonymous_exps) < 1);

		    printf("<TD width=10%>%s</TD><TD width=10%>gid=%s</TD><TD width=10%>qid=%s</TD><TD width=10%>gdf=%.2f</TD><TD width=10%>qtf=%.2f</TD><TD width=*>%s</TD></TR>\n",
			   $str,
			   $gid,
			   $qid,
			   $gdf,
			   $qtf,
			   join("<BR>\n", @synonymous_exps)
			);
		} else {
		    printf(qq(<TD>%s</TD><TD>%s</TD><TD>%s</TD><TD>%.3f</TD><TD>%.3f</TD><TD>%.3f</TD><TD>???</TD></TR>\n),
			   $str,
			   $qid,
			   $str,
			   $gdf,
			   $qtf);
		}
	    }
	}
    }

    print "</TABLE>\n";
}

sub print_for_XML {
    my ($this) = @_;

    print qq(<TOOL_OUTPUT>\n);
    print qq(<KNP format="tree">\n);
    print "<![CDATA[\n";
    $this->{knp_result}->draw_tag_tree(<STDOUT>);
    print "]]>\n";
    print qq(</KNP>\n);

    print qq(<KNP format="tab">\n);
    print "<![CDATA[\n";
    print $this->{knp_result}->all_dynamic . "\n";
    print "]]>\n";
    print qq(</KNP>\n);

    if ($this->{syn_result}) {
	my $ret = $this->{syn_result};
	# $ret =~ s/</&lt;/g;

	print qq(<SynGraph format="tab">\n);
	print "<![CDATA[\n";
	print $ret . "\n";
	print "]]>\n";
	print qq(</SynGraph>\n);
    }
    print qq(</TOOL_OUTPUT>\n);
}

# デバッグ用プリント
sub debug_print {
    my ($this) = @_;

    use Dumper;
    print "<TABLE border=1>\n";
    foreach my $type ('words', 'dpnds') {
	foreach my $words (@{$this->{$type}}) {
	    foreach my $rep (@$words) {
		my $flag = ($rep->{requisite}) ? '●' : (($rep->{optional}) ? '▲' : '×');
		printf ("<TR><TD>%s</TD><TD>%s</TD><TD>%d</TD></TR>\n", $flag, $rep->{string}, $rep->{df});
	    }
	}
    }
    print "</TABLE>\n";
}


# 文字列表現を返すメソッド
sub to_string {
    my ($this) = @_;

    my $words_str = "WORDS:\n";
    foreach my $ws (@{$this->{words}}) {
	my $reps = "(";
	foreach my $w (@{$ws}) {
	    if ($w->{isBasicNode}) {
		$reps .= "$w->{string}\[$w->{qid}][B] ";
	    } else {
		$reps .= "$w->{string}\[$w->{qid}] ";
	    }
	}
	chop($reps);
	$reps .= ")\n";
	$words_str .= " $reps";
    }

    my $dpnds_str = "DPNDS:\n";
    foreach my $ds (@{$this->{dpnds}}) {
	my $reps = "(";
	foreach my $d (@{$ds}) {
	    if ($d->{isBasicNode}) {
		$reps .= "$d->{string}\[qid=$d->{qid}][B] ";
	    } else {
		$reps .= "$d->{string}\[qid=$d->{qid}] ";
	    }
	}
	chop($reps);
	$reps .= ")\n";
	$dpnds_str .= " $reps";
    }

    my $ret .= ($words_str . "\n");
    $ret .= ($dpnds_str . "\n");
    $ret .= "LOGICAL_COND: $this->{logical_cond_qkw}\n";
    if ($this->{sentence_flag} > 0) {
	$ret .= "NEAR_SENT: $this->{near}\n";
    } else {
	$ret .= "NEAR_WORD: $this->{near}\n";
    }
    $ret .= "FORCE_DPND: $this->{force_dpnd}";

    return $ret;
}


sub get_parse_tree {
    my ($this) = @_;

    return $this->{parse_tree};
}

sub print_tree_view {
    my ($this) = @_;

    $this->{knp_result}->draw_tag_tree(<STDOUT>);
}

sub print_table_view {
    my ($this) = @_;

    print $this->{knp_result}->all_dynamic;
}

sub get_knp_result {
    my ($this) = @_;

    return $this->{knp_result}->all_dynamic;
}

sub to_string_verbose {
    my ($this) = @_;

    my $words_str = "WORDS:\n";
    foreach my $ws (@{$this->{words}}) {
	my $flag = '    ';
	my $reps = "(";
	my $NE_flag = '  ';
	my $QT_flag = '　　';
	my $max_df = -1;
	my $max_dfrank = -1;
	my $head_flag = '　　';
	my $weight_flag = '　　　';
	my $reason;
	foreach my $w (@{$ws}) {
	    $reps .= "$w->{string}\[gid=$w->{gid}, qid=$w->{qid}, df=$w->{df}, weight=$w->{weight}, isContentWord=$w->{isContentWord}";
	    $max_df = $w->{df} if ($w->{df} > $max_df);
	    $max_dfrank = $w->{df_rank} if ($w->{df_rank} > $max_dfrank);

	    if ($w->{NE}) {
		$reps .= ", NE=$w->{NE}";
		$NE_flag = 'NE';
	    }

	    if ($w->{question_type}) {
		$reps .= ", QTYPE=$w->{question_type}";
		$QT_flag = '文末';
	    }

	    $head_flag = '主辞' if ($w->{lexical_head});

	    $reps .= ", isBasicNode" if ($w->{isBasicNode});
	    $reps .= ", NE-SYN" if ($w->{fstring} =~ /<削除::NEのSYNノード>/);
	    $reps .= "], ";

	    if ($w->{discarded}) {
		$flag = '削除';
		$reason .= "★$w->{reason} ";
	    }

	    if ($w->{weight_changed}) {
		$weight_flag = 'Ｗ変更';
		$reason .= "★$w->{reason} ";
	    }
	    $flag = '必須' if ($w->{requisite});
	}
	chop($reps);
	chop($reps);
	$reps .= ")";
	$words_str .= sprintf(" %s %s %s %s %s %3s %s\t%s\n", $flag, $weight_flag, $NE_flag, $QT_flag, $head_flag, $max_dfrank, $reps, $reason);
    }

    my $dpnds_str = "DPNDS:\n";
    foreach my $ds (@{$this->{dpnds}}) {
	my $flag = '    ';
	my $max_dfrank = -1;
	my $reps = "(";
	my $reason;
	my $weight_flag = "　　　";
	foreach my $d (@{$ds}) {
	    $reps .= "$d->{string}\[gid=$d->{gid}, qid=$d->{qid}, df=$d->{df}, weight=$d->{weight}";
#	    $reps .= "$d->{string}\[qid=$d->{qid}, df=$d->{df}";
	    $reps .= ", isBasicNode" if ($d->{isBasicNode});
	    $reps .= "], ";

	    if ($d->{discarded}) {
		$flag = '削除';
		$reason .= "★ $d->{reason} ";
	    }

	    if ($d->{weight_changed}) {
		$weight_flag = 'Ｗ変更';
		$reason .= "★$d->{reason} ";
	    }

	    $flag = '必須' if ($d->{requisite});
	}
	chop($reps);
	chop($reps);
	$reps .= ")";

	$dpnds_str .= sprintf(" %s %s                  %s\t%s\n", $flag, $weight_flag, $reps, $reason);
    }

    my $ret = "STRING:\n$this->{midasi}\n";
    $ret .= ($words_str . "\n");
    $ret .= ($dpnds_str . "\n");

    return $ret;
}

sub to_string_verbose_XML {
    my ($this) = @_;

    my $reps;
    $reps .= "<INDEX>\n";
    $reps .= "<WORD_INDEX>\n";
    foreach my $ws (@{$this->{words}}) {
 	$ws->[0]{NE} =~ s/^<//;
 	$ws->[0]{NE} =~ s/>$//;
 	$ws->[0]{question_type} =~ s/^<//;
 	$ws->[0]{question_type} =~ s/>$//;

	my $repbufs;
	my %reasons = ();
	foreach my $w (@{$ws}) {
	    foreach my $r (split(/ /, $w->{reason})) {
		$reasons{$r} = 1;
	    }
	    my $string = $w->{string};
	    $string =~ s/</＜/g;
	    $string =~ s/>/＞/g;

 	    $repbufs .= sprintf(qq(<WORD string="%s" qid="%d" freq="%.3f" df="%.2f" isBasicNode="%s" isSynNodeOfNE="%s" />\n),
				$string,
				$w->{qid},
				$w->{freq},
				$w->{df},
				($w->{isBasicNode}) ? 'yes' : 'no',
				($w->{fstring} =~ /<削除::NEのSYNノード>/) ? 'yes' : 'no');
	}

 	$reps .= sprintf(qq(<WORDS gid="%d" weight="%.3f" isContentWord="%s" isNE="%s" questionType="%s" isHead="%s" isRequisite="%s" reason="%s">\n),
			 $ws->[0]{gid},
			 $ws->[0]{weight},
			 ($ws->[0]{isContentWord}) ? 'yes' : 'no',
			 ($ws->[0]{NE}) ? $ws->[0]{NE} : 'no',
			 ($ws->[0]{question_type}) ? $ws->[0]{question_type} : 'no',
			 ($ws->[0]{lexical_head}) ? 'yes' : 'no',
			 ($ws->[0]{requisite}) ? 'yes' : 'no',
			 (scalar(keys (%reasons))) ? join(',', keys (%reasons)) : 'no');
	$reps .= $repbufs;
	$reps .= "</WORDS>\n";
    }
    $reps .= "</WORD_INDEX>\n";

    $reps .= "<DEPENDENCY_INDEX>\n";
    foreach my $ds (@{$this->{dpnds}}) {
	my $repbufs;
	my %reasons = ();
	foreach my $d (@{$ds}) {
	    foreach my $r (split(/ /, $d->{reason})) {
		$reasons{$r} = 1;
	    }

	    my $string = $d->{string};
	    $string =~ s/</＜/g;
	    $string =~ s/>/＞/g;

 	    $repbufs .= sprintf(qq(<DPND string="%s" qid="%d" freq="%.3f" df="%.2f" isBasicNode="%s" />\n),
				$string,
				$d->{qid},
				$d->{freq},
				$d->{df},
				($d->{isBasicNode}) ? 'yes' : 'no');
	}

 	$reps .= sprintf(qq(<DPNDS gid="%d" weight="%.3f" reason="%s">\n),
			 $ds->[0]{gid},
			 $ds->[0]{weight},
			 (scalar(keys (%reasons))) ? join(',', keys (%reasons)) : 'no');
	$reps .= $repbufs;
	$reps .= "</DPNDS>\n";
    }
    $reps .= "</DEPENDENCY_INDEX>\n";
    $reps .= "</INDEX>\n";

    return $reps;
}

sub to_string_simple {
    my ($this) = @_;

    my @ret;
    foreach my $ws (@{$this->{words}}) {
	my $reps = "(";
	foreach my $w (@{$ws}) {
	    $reps .= "$w->{string},";
	}
	chop($reps);
	$reps .= ")";
	push(@ret, $reps);
    }

    foreach my $ds (@{$this->{dpnds}}) {
	my $reps = "(";
	foreach my $d (@{$ds}) {
	    $reps .= "$d->{string},";
	}
	chop($reps);
	$reps .= ")";
	push(@ret, $reps);
    }

    return join(':', @ret);
}

sub normalize {
    my ($this) = @_;

    my @buf;
    foreach my $memberName (sort {$a cmp $b} keys %$this) {
	next if ($memberName eq 'words');
	next if ($memberName eq 'dpnds');
	next if ($memberName eq 'knp_result');
	next if ($memberName eq 'syn_result');
	next if ($memberName eq 'logger');

	push(@buf, $memberName . '=' . $this->{$memberName});
    }

    return join(',', @buf);
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
    my ($this, $i, $tag, $tid2syns, $syngraph) = @_;


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
		unless ($this->{disable_synnode}) {
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


sub getPaintingJavaScriptCode {
    my ($this, $colorOffset) = @_;

    ###### 変数の初期化 #####

    my $REQUISITE = '<クエリ必須語>';
    my $OPTIONAL  = '<クエリ不要語>';
    my $IGNORE    = '<クエリ削除語>';
    my $REQUISITE_DPND = '<クエリ必須係り受け>';



    my $font_size = 12;
    my $offsetX = 10 + 24;
    my $offsetY = $font_size * (scalar(@{$this->{words}}) + 3);
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
    my @kihonkus = $this->{syn_result}->tag;
    my $syngraph = Configure::getSynGraphObj();
    
    my %tid2syns = ();
    for (my $i = 0; $i < scalar(@kihonkus); $i++) {
	my $tag = $kihonkus[$i];

	my $gid = ($tag->synnodes)[0]->tagid;
	$gid2num{$gid} = $i;

	my ($synbuf, $max_num_of_words) = $this->_getExpressions($i, $tag, \%tid2syns, $syngraph);

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
	$jscode .= qq(jg.drawStringRect(\'$mark\', $offsetX, $offsetY - 1.5 * $font_size, $font_size, 'left');\n);
	$offsetX += ($width + $synbox_margin);
    }
    $colorOffset += scalar(@{$this->{words}});


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
    $jscode .= qq(jg.drawStringRect(\'$mark\', $x1, $y - 1.5 * $font_size, $font_size, 'left');\n);

    return $jscode;
}

# デストラクタ
sub DESTROY {}

1;
