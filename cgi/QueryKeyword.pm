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
use Tsubaki::QueryAnalyzer;


my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class, $string, $sentence_flag, $is_phrasal_search, $near, $keep_order, $force_dpnd, $logical_cond_qkw, $syngraph, $opt) = @_;
    my $this = {
	words => [],
	dpnds => [],
	sentence_flag => $sentence_flag,
	is_phrasal_search => $is_phrasal_search,
	near => $near,
	keep_order => $keep_order,
	force_dpnd => $force_dpnd,
	logical_cond_qkw => $logical_cond_qkw,
	rawstring => $string,
	syngraph => $syngraph,
	disable_dpnd => $opt->{disable_dpnd},
	disable_synnode => $opt->{disable_synnode}
    };

    unless ($string) {
	print "Empty query !<BR>\n";
	exit;
    }

    my $knpresult;
    try {
	$knpresult = $opt->{knp}->parse($string);
    }
    catch Error with {
	my $err = shift;
	print "Bad query: $string<BR>\n";
	print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
	print "Dumpping messages of KNP object is following.<BR>\n";
	print Dumper($opt->{knp}) . "<BR>\n";
	exit;
    };

    unless (defined $knpresult) {
	print "Can't parse the query: $string<BR>\n";
	exit;
    }



    if ($opt->{telic_process} || $opt->{CN_process} || $opt->{NE_process} || $opt->{modifier_of_NE_process}) {
	my $analyzer = new Tsubaki::QueryAnalyzer($opt);
	$analyzer->analyze($knpresult,
			   {
			       telic_process => $opt->{telic_process},
			       CN_process => $opt->{CN_process},
			       NE_process => $opt->{NE_process},
			       modifier_of_NE_process => $opt->{modifier_of_NE_process}
			   });
    }

    $this->{knp_result} = $knpresult;

    my %buff;
    my $indice;
    unless ($opt->{syngraph}) {
	# KNP 結果から索引語を抽出
	$indice = $opt->{indexer}->makeIndexFromKNPResult($knpresult->all);
    } else {
	# SynGraph 結果から索引語を抽出
 	$knpresult->set_id(0);
 	my $synresult = $opt->{syngraph}->OutputSynFormat($knpresult, $opt->{syngraph_option}, $opt->{syngraph_option});
	$this->{syn_result} = new KNP::Result($synresult);

	$indice = $opt->{indexer}->makeIndexFromSynGraphResultObject($this->{syn_result},
 							 { use_of_syngraph_dependency => $CONFIG->{USE_OF_SYNGRAPH_DEPENDENCY},
 							   use_of_hypernym => $CONFIG->{USE_OF_HYPERNYM},
 							   disable_synnode => $opt->{disable_synnode},
							   force_dpnd => $this->{force_dpnd},
							   string_mode => 0,
 							   use_of_negation_and_antonym => $CONFIG->{USE_OF_NEGATION_AND_ANTONYM},
							   antonym_and_negation_expansion => $opt->{antonym_and_negation_expansion}
 							 });
    }



    # Indexer.pm より返される索引語を同じ代表表記・SYNノードごとにまとめる
    foreach my $idx (@{$indice}) {
	$buff{$idx->{group_id}} = [] unless (exists($buff{$idx->{group_id}}));
	push(@{$buff{$idx->{group_id}}}, $idx);
    }

    foreach my $group_id (sort {$buff{$a}->[0]{pos} <=> $buff{$b}->[0]{pos}} keys %buff) {
	my @word_reps;
	my @dpnd_reps;

	foreach my $m (@{$buff{$group_id}}) {
	    # 近接条件が指定されていない かつ 機能語 の場合は検索に用いない
	    next if ($m->{isContentWord} < 1 && $this->{is_phrasal_search} < 0);

	    # OR 検索が指定されていた場合の処理
	    if ($this->{logical_cond_qkw} eq 'OR') {
		$m->{requisite} = 0;
		$m->{optional} = 1;
	    }

	    if ($m->{midasi} =~ /\-\>/) {
		push(@dpnd_reps, {
		    string => $m->{midasi},
		    gid => $group_id,
		    qid => -1,
		    weight => 1,
		    freq => $m->{freq},
		    requisite => $m->{requisite},
		    optional => $m->{optional},
		    isContentWord => $m->{isContentWord},
		    isBasicNode => $m->{isBasicNode}
		     });
	    } else {
		push(@word_reps, {
		    surf => $m->{surf},
		    string => $m->{midasi},
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
		    fstring => $m->{fstring}
		     });
	    }
	}

	push(@{$this->{words}}, \@word_reps) if (scalar(@word_reps) > 0);
	push(@{$this->{dpnds}}, \@dpnd_reps) if (scalar(@dpnd_reps) > 0);
    }


#     文レベルでの近接制約でない場合は、キーワード内の形態素数を考慮する
#     if ($this->{near} > -1 && $this->{sentence_flag} < 0) {
# 	$this->{near} += scalar(@{$this->{words}});
#     }

    if ($is_phrasal_search > 0) {
	$this->{near} = scalar(@{$this->{words}});
    }

    bless $this;
}


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
    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.mod.cdb\n";

    printf(qq(<H4 style="background-color:black; color: white;"><A name="query">クエリの解析結果</A></H4>\n));
    print qq(<TABLE border="1" width="100%">\n);
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
		    my @synonymous_exps = split(/\|+/, decode('utf8', $synonyms{$str}));
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
    untie %synonyms;
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
#     $ret .= "LOGICAL_COND: $this->{logical_cond_qkw}\n";
#     if ($this->{sentence_flag} > 0) {
# 	$ret .= "NEAR_SENT: $this->{near}\n";
#     } else {
# 	$ret .= "NEAR_WORD: $this->{near}\n";
#     }
#     $ret .= "FORCE_DPND: $this->{force_dpnd}";

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

	push(@buf, $memberName . '=' . $this->{$memberName});
    }

    return join(',', @buf);
}

sub getPaintingJavaScriptCode {
    my ($this, $colorOffset) = @_;


    my $REQUISITE = '<クエリ必須語>';
    my $OPTIONAL  = '<クエリ不要語>';
    my $IGNORE    = '<クエリ削除語>';
    my $REQUISITE_DPND = '<クエリ必須係り受け>';



    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.mod.cdb\n";

    my $font_size = 12;
    my $offsetX = 10 + 24;
    my $offsetY = $font_size * (scalar(@{$this->{words}}) + 2);
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
    

    my $jscode .= qq(jg.clear();\n);

    # 単語・同義表現グループを描画する
    my $max_num_of_synonyms = 0;
    my %gid2pos = ();
    my %gid2num = ();
    my @kihonkus = $this->{syn_result}->tag;
    for (my $i = 0; $i < scalar(@kihonkus); $i++) {
	my $tag = $kihonkus[$i];

	# 同義グループに属す表現を取得と幅（文字数）の取得

	my $basicNode = undef;
	my $surf;
	my %synbuf;
	my $surf = ($tag->synnodes)[0]->midasi;
	my $max_num_of_words = length($surf);
	my $gid = ($tag->synnodes)[0]->tagid;
	$gid2num{$gid} = $i;
	unless ($tag->fstring() =~ /<クエリ削除語>/) {
	    foreach my $synnodes ($tag->synnodes) {
		foreach my $node ($synnodes->synnode) {
		    next if ($node->feature =~ /<上位語>/);
		    next if ($node->feature =~ /<反義語>/);
		    next if ($node->feature =~ /<否定>/);

		    my $str = $node->synid;
		    ($str) = ($node->synid =~ /(.+)\/.+/) if ($str =~ /\//);
		    $basicNode = $str if ($str !~ /s\d+/ && !defined $basicNode);

		    # 同義グループに属す表現を取得
		    unless ($this->{disable_synnode}) {
			foreach my $w (split('\|', $synonyms{$str})) {
			    $w = decode('utf8', $w);
			    $w =~ s/\[.+?\]//;
			    $w =~ s/\/.+//;
			    $synbuf{$w} = 1;
			    $max_num_of_words = length($w) if ($max_num_of_words < length($w));
			}
		    }
		}
	    }
	}
	# 出現形、基本ノードと同じ表現は削除する
	delete($synbuf{$surf});
	delete($synbuf{$basicNode});

	my $width = $font_size * (1.5 + $max_num_of_words);
	# 同義グループのX軸の中心座標を保持（係り受けの線を描画する際に利用する）
	$gid2pos{$gid}->{pos} = $offsetX + int(0.5 * $width);
	$gid2pos{$gid}->{num_child} = 0;
	$gid2pos{$gid}->{num_parent} = 1;

	# 下に必須・オプショナルのフラグを取得
#	my $rep = $this->{words}[$i][0];
	my $mark = ($tag->fstring() =~ /クエリ削除語/) ? '×' : (($tag->fstring() =~ /クエリ不要語/) ?  '△' : '○');
	my $colorIndex = ($i + $colorOffset) % scalar(@stylecolor);

	my $synbox;
	if ($tag->fstring() =~ /<クエリ削除語>/) {
	    $synbox .= sprintf(qq(<TABLE style=\\'font-size: $font_size; margin: 0px;text-align: center; $removedcolor\\' width=%dpx>), $width);
	} else {
	    $synbox .= sprintf(qq(<TABLE style=\\'font-size: $font_size; margin: 0px;text-align: center; $stylecolor[$colorIndex]\\' width=%dpx>), $width);
	}

	if (scalar(keys %synbuf) > 0) {
	    my $rate = 36;
	    my ($r, $g, $b) = ($bgcolor[$colorIndex] =~ /#(..)(..)(..);/);
	    $r = (hex($r) + $rate > 255) ? 'ff' : sprintf ("%x", hex($r) + $rate);
	    $g = (hex($g) + $rate > 255) ? 'ff' : sprintf ("%x", hex($g) + $rate);
	    $b = (hex($b) + $rate > 255) ? 'ff' : sprintf ("%x", hex($b) + $rate);
	    my $dilutedColor = sprintf("#%s%s%s", $r, $g, $b);

	    $synbox .= sprintf(qq(<TR><TD style=\\'border-bottom: 1px solid %s;\\'>%s</TD></TR>), $color[$colorIndex], $surf);
	    $synbox .= sprintf(qq(<TR><TD style=\\'background-color: %s;\\'>%s</TD></TR>), $dilutedColor, join("<BR>", keys %synbuf));
	} else {
	    $synbox .= sprintf(qq(<TR><TD>%s</TD></TR>), $surf);
	}
	$synbox .= "</TABLE>";

	$max_num_of_synonyms = scalar(keys %synbuf) if ($max_num_of_synonyms < scalar(keys %synbuf));

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
	$kakarisaki = $kakarisaki->parent if (defined $kakarisaki && $kakarimoto->dpndtype eq 'P');
	next unless (defined $kakarisaki);

	if ($kakarisaki->fstring() =~ /<クエリ不要語>/ &&
	    $kakarisaki->fstring() !~ /<クエリ削除語>/ &&
	    $kakarisaki->fstring() !~ /<固有表現を修飾>/) {
	    my $_kakarisaki = $kakarisaki->parent();
	    next unless (defined $_kakarisaki);

	    my $mark = ($kakarisaki->fstring() =~ /クエリ削除語/) ?  '×' : '△';
	    $jscode .= &getDrawingDependencyCode($i, $kakarimoto, $_kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, \%gid2num, \%gid2pos);
	}

	my $mark = ($kakarimoto->fstring() =~ /クエリ必須係り受け/) ?  '○' : (($kakarimoto->fstring() =~ /クエリ削除係り受け/) ? '×' : '△');
	$jscode .= &getDrawingDependencyCode($i, $kakarimoto, $kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, \%gid2num, \%gid2pos);
    }


    $jscode .= qq(jg.setFont(\'ＭＳゴシック\', \'$font_size\', 0);\n);
    $jscode .= qq(jg.paint();\n);

    untie %synonyms;

    return ($width, $height, $colorOffset, $jscode);
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

    if ($mark eq '×') {
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


sub getPaintingJavaScriptCode2 {
    my ($this, $colorOffset) = @_;

    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.mod.cdb\n";

    my $font_size = 12;
    my $offsetX = 10 + 24;
    my $offsetY = $font_size * (scalar(@{$this->{words}}) + 2);
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
    
    my %buff;
    my $size = scalar (@{$this->{dpnds}});
    my %dupcheck;
    for (my $i = 0; $i < $size; $i++) {
	my $dpnds = $this->{dpnds}[$i];
	foreach my $dpnd (@$dpnds) {
	    my $k = $dpnd->{kakarimoto_gid} . ":" . $dpnd->{kakarisaki_gid};
	    next if (exists $dupcheck{$k});

	    $buff{$dpnd->{kakarimoto_gid}}->{kakarimoto}++;
	    $buff{$dpnd->{kakarisaki_gid}}->{kakarisaki}++;
	    $dupcheck{$k} = 1;
	}
    }


    my $jscode .= qq(jg.clear();\n);

    # 単語・同義表現グループを描画する
    my $max_num_of_synonyms = 0;
    my %gid2pos = ();
    for (my $i = 0; $i < scalar(@{$this->{words}}); $i++) {

	# 同義グループに属す表現を取得と幅（文字数）の取得
	
	my $gid;
	my $basicNode;
	my $surf;
	my %synbuf;
	my $max_num_of_words = 1;
	foreach my $rep (@{$this->{words}[$i]}) {
	    my $str = $rep->{string};
	    $gid = $rep->{gid};

	    if ($rep->{isBasicNode}) {
		$basicNode = $str;
		$surf = $rep->{surf};
		$max_num_of_words = length($str) if ($max_num_of_words < length($str));
		$max_num_of_words = length($surf) if ($max_num_of_words < length($surf));
		next;
	    }

	    # 同義グループに属す表現を取得
	    foreach my $w (split('\|', $synonyms{$str})) {
		$w =~ s/\[.+?\]//;
		$w =~ s/\/.+//;
		$synbuf{$w} = 1;
		$max_num_of_words = length($w) if ($max_num_of_words < length($w));
	    }
	}

	# 出現形、基本ノードと同じ表現は削除する
	delete($synbuf{$basicNode});
	delete($synbuf{$surf});

	my $width = $font_size * (1.5 + $max_num_of_words);
	# 同義グループのX軸の中心座標を保持（係り受けの線を描画する際に利用する）
	$gid2pos{$gid} = $offsetX + int(0.5 * $width);

	# 下に必須・オプショナルのフラグを取得
	my $rep = $this->{words}[$i][0];
	my $mark = ($rep->{requisite}) ?  '○' :  ($rep->{optional}) ? '△' : '？';
	my $colorIndex = ($i + $colorOffset) % scalar(@stylecolor);

	my $synbox;
	$synbox .= sprintf(qq(<TABLE style=\\'font-size: $font_size; margin: 0px;text-align: center; $stylecolor[$colorIndex]\\' width=%dpx>), $width);
	if (scalar(keys %synbuf) > 0) {
	    my $rate = 36;
	    my ($r, $g, $b) = ($bgcolor[$colorIndex] =~ /#(..)(..)(..);/);
	    $r = (hex($r) + $rate > 255) ? 'ff' : sprintf ("%x", hex($r) + $rate);
	    $g = (hex($g) + $rate > 255) ? 'ff' : sprintf ("%x", hex($g) + $rate);
	    $b = (hex($b) + $rate > 255) ? 'ff' : sprintf ("%x", hex($b) + $rate);
	    my $dilutedColor = sprintf("#%s%s%s", $r, $g, $b);

	    $synbox .= sprintf(qq(<TR><TD style=\\'border-bottom: 1px solid %s;\\'>%s</TD></TR>), $color[$colorIndex], $surf);
	    $synbox .= sprintf(qq(<TR><TD style=\\'background-color: %s;\\'>%s</TD></TR>), $dilutedColor, join("<BR>", keys %synbuf));
	} else {
	    $synbox .= sprintf(qq(<TR><TD>%s</TD></TR>), $surf);
	}
	$synbox .= "</TABLE>";

	$max_num_of_synonyms = scalar(keys %synbuf) if ($max_num_of_synonyms < scalar(keys %synbuf));

	$jscode .= qq(jg.drawStringRect(\'$synbox\', $offsetX, $offsetY, $width, 'left');\n);
	$jscode .= qq(jg.drawStringRect(\'$mark\', $offsetX, $offsetY - 1.5 * $font_size, $font_size, 'left');\n);
	$offsetX += ($width + $synbox_margin);
    }
    $colorOffset += scalar(@{$this->{words}});


    # 解析結果を表示するウィンドウの幅、高さを求める
    my $width = $offsetX;
    my $height = $offsetY + int(($max_num_of_synonyms + 1) * 1.1 * $font_size); # +1 は●▲の分, *1.1 は行間


    # 係り受けの線の起点の位置を計算
    # 係り受けの距離が近いものは→←
    # 係り受けの距離が遠いものは←→
    my %gid2poss;
    my $margin = $arrow_size + 3;
    foreach my $gid (keys %buff) {
	my $num_of_kakarisaki = $buff{$gid}->{kakarisaki};
	my $num_of_kakarimoto = $buff{$gid}->{kakarimoto};

	for (my $i = 0; $i < $num_of_kakarisaki; $i++) {
	    push(@{$gid2poss{$gid}}, $gid2pos{$gid} - ($margin * ($i + 1)));
	}

	for (my $i = 0; $i < $num_of_kakarimoto; $i++) {
	    push(@{$gid2poss{$gid}}, $gid2pos{$gid} + ($margin * $i));
	}
    }

#     my $dumpstr = Dumper(\%buff);
#     $jscode .= qq(/* $dumpstr */\n);

#     my $dumpstr = Dumper(\%gid2poss);
#     $jscode .= qq(/* $dumpstr */\n);


    # 係り受け関係を描画する
    %dupcheck = ();
    for (my $i = 0; $i < $size; $i++) {
	my $dpnd_reps = $this->{dpnds}[$i];
	foreach my $rep (@$dpnd_reps) {
	    my $k = $rep->{kakarimoto_gid} . ":" . $rep->{kakarisaki_gid};
	    next if (exists $dupcheck{$k});
	    $dupcheck{$k} = 1;

	    my $x1 = shift @{$gid2poss{$rep->{kakarimoto_gid}}};
	    my $x2 = shift @{$gid2poss{$rep->{kakarisaki_gid}}};

	    my $gid1 = $rep->{kakarimoto_gid};
	    my $gid2 = $rep->{kakarisaki_gid};
	    my $dist = abs(10 * ($gid2 - $gid1));

	    my $y = $offsetY - $font_size - (1.5 * $dist * $font_size);


	    # 係り受けの線をひく

	    # コメントの出力
# 	    $jscode .= qq(/* parent=$gid1, child=$gid2, dist=$dist */\n);
# 	    my $dumpstr = Dumper($rep);
# 	    $jscode .= qq(/* $dumpstr */\n);

	    $jscode .= qq(jg.drawLine($x1, $offsetY, $x1, $y);\n);
	    $jscode .= qq(jg.drawLine($x1 - 1, $offsetY, $x1 - 1, $y);\n);

	    $jscode .= qq(jg.drawLine($x1, $y, $x2, $y);\n);
	    $jscode .= qq(jg.drawLine($x1, $y - 1, $x2, $y - 1);\n);

	    $jscode .= qq(jg.drawLine($x2, $y, $x2, $offsetY);\n);
	    $jscode .= qq(jg.drawLine($x2 + 1, $y, $x2 + 1, $offsetY);\n);

	    # 矢印
	    $jscode .= qq(jg.fillPolygon(new Array($x2, $x2 + $arrow_size, $x2 - $arrow_size), new Array($offsetY, $offsetY - $arrow_size, $offsetY - $arrow_size));\n);


	    # 線の上に必須・オプショナルのフラグを描画する
	    my $mark = ($rep->{requisite}) ?  '○' :  ($rep->{optional}) ? '△' : '？';
	    $jscode .= qq(jg.drawStringRect(\'$mark\', $x1, $y - 1.5 * $font_size, $font_size, 'left');\n);
	    # $jscode .= qq(jg.drawStringRect(\'$mark\', $x1 + 0.5 * ($x2 - $x1) - $font_size * 0.5, $y, $font_size, 'center');\n);
	    # $jscode .= qq(jg.drawStringRect(\'$mark\', $x1 - $font_size - 5, $y, $font_size, 'center');\n);
	}
    }


    $jscode .= qq(jg.setFont(\'ＭＳゴシック\', \'$font_size\', 0);\n);
    $jscode .= qq(jg.paint();\n);

    untie %synonyms;

    return ($width, $height, $colorOffset, $jscode);
}

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

1;
