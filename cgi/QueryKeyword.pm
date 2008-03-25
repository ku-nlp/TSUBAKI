package QueryKeyword;

#$Id$

# 1つの検索語を表すクラス

use strict;
use utf8;
use Encode;
use Data::Dumper;

# コンストラクタ
sub new {
    my ($class, $string, $sentence_flag, $is_phrasal_search, $near, $force_dpnd, $logical_cond_qkw, $syngraph, $opt) = @_;
    my $this = {
	words => [],
	dpnds => [],
	sentence_flag => $sentence_flag,
	is_phrasal_search => $is_phrasal_search,
	near => $near,
	force_dpnd => $force_dpnd,
	logical_cond_qkw => $logical_cond_qkw,
	rawstring => $string,
	syngraph => $syngraph
    };

    my $indice;
    my $knpresult = $opt->{knp}->parse($string);

    if ($opt->{trimming}) {
	my $trimmer = new QueryTrimmer();
	$trimmer->trim($knpresult);
    }

#   $this->{parse_tree} = $knpresult
    $this->{knp_result} = $knpresult;

    my %buff;
    unless ($opt->{syngraph}) {
	# KNP 結果から索引語を抽出
	$indice = $opt->{indexer}->makeIndexFromKNPResult($knpresult);
	# $indice = $opt->{indexer}->make_index_from_KNP_result_object($knpresult);
    } else {
	# SynGraph 結果から索引語を抽出
 	$knpresult->set_id(0);
 	my $synresult = $opt->{syngraph}->OutputSynFormat($knpresult, $opt->{syngraph_option});
	my @content_words = ();
	foreach my $tag ($knpresult->tag) {
	    foreach my $mrph ($tag->mrph) {
		if ($mrph->fstring =~ /<意味有|内容語>/) {
		    push(@content_words, $mrph);
		    last;
		}
	    }
	}

	$indice = $opt->{indexer}->makeIndexfromSynGraph($synresult, \@content_words);
    }

    # Indexer.pm より返される索引語を同じ代表表記ごとにまとめる
    foreach my $idx (@{$indice}) {
	$buff{$idx->{group_id}} = [] unless (exists($buff{$idx->{group_id}}));
	push(@{$buff{$idx->{group_id}}}, $idx);
    }

    foreach my $group_id (sort {$buff{$a}->[0]{pos}[0] <=> $buff{$b}->[0]{pos}[0]} keys %buff) {
	my @word_reps;
	my @dpnd_reps;
	foreach my $m (@{$buff{$group_id}}) {
	    # 近接条件が指定されていない かつ 機能語 の場合は検索に用いない
	    next if ($m->{isContentWord} < 1 && $this->{is_phrasal_search} < 0);

	    if ($m->{midasi} =~ /\-\>/) {
		push(@dpnd_reps, {string => $m->{midasi},
				  gid => $group_id,
				  qid => -1,
				  weight => 1,
				  freq => $m->{freq},
				  isContentWord => $m->{isContentWord},
				  isBasicNode => $m->{isBasicNode}
		     });
	    } else {
		push(@word_reps, {string => $m->{midasi},
				  gid => $group_id,
				  qid => -1,
				  weight => 1,
				  freq => $m->{freq},
				  isContentWord => $m->{isContentWord},
				  question_type => $m->{question_type},
				  NE => $m->{NE},
				  isBasicNode => $m->{isBasicNode},
				  fstring => $m->{fstring}
		     });

		unless ($m->{isContentWord}) {
		    $word_reps[-1]->{discarded} = 1;
		    $word_reps[-1]->{reason} = "<意味無> ";
		}
	    }
	}
	push(@{$this->{words}}, \@word_reps) if (scalar(@word_reps) > 0);
	push(@{$this->{dpnds}}, \@dpnd_reps) if (scalar(@dpnd_reps) > 0);
    }

    if ($is_phrasal_search > 0) {
	$this->{near} = scalar(@{$this->{words}});
    }

    bless $this;
}

# デストラクタ
sub DESTROY {}

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

#   my $ret = "STRING:\n$this->{midasi}\n";
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
#	    $reps .= "$w->{string}\[qid=$w->{qid}, df=$w->{df}, rank_df=$w->{df_rank}";
	    $reps .= "$w->{string}\[qid=$w->{qid}, df=$w->{df}, weight=$w->{weight}, isContentWord=$w->{isContentWord}";
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
	    $reps .= "$d->{string}\[qid=$d->{qid}, df=$d->{df}, weight=$d->{weight}";
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
#     $ret .= "LOGICAL_COND: $this->{logical_cond_qkw}\n";
#     if ($this->{sentence_flag} > 0) {
# 	$ret .= "NEAR_SENT: $this->{near}\n";
#     } else {
# 	$ret .= "NEAR_WORD: $this->{near}\n";
#     }
#     $ret .= "FORCE_DPND: $this->{force_dpnd}";

    return $ret;
}

1;
