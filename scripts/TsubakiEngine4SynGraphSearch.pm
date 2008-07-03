package TsubakiEngine4SynGraphSearch;

# $Id$

# SynGraph 検索を行うクラス

use strict;
use Retrieve;
use Storable qw(store retrieve);
use Encode;
use utf8;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}

# TsubakiEngine を継承する
use TsubakiEngine;
@TsubakiEngine4SynGraphSearch::ISA = qw(TsubakiEngine);



# コンストラクタ
sub new {
    my ($class, $opts) = @_;
    my $obj = $class->SUPER::new($opts);

    # DAT ファイルから単語を含む文書を検索する retriever オブジェクトをセットする
    $obj->{word_retriever} = new Retrieve($opts->{idxdir}, 'word', $opts->{skip_pos}, $opts->{verbose}, 0, $opts->{show_speed});

    # DAT ファイルから係り受けを含む文書を検索する retriever オブジェクトをセットする
    $obj->{dpnd_retriever} = new Retrieve($opts->{idxdir}, 'dpnd', $opts->{skip_pos}, $opts->{verbose}, 1, $opts->{show_speed});

    # 検索にアンカーテキストを考慮する
    print $opts->{idxdir4anchor} . "\n";
    $obj->{word_retriever4anchor} = new Retrieve($opts->{idxdir4anchor}, 'word', 1, $opts->{verbose}, $opts->{show_speed});
    $obj->{dpnd_retriever4anchor} = new Retrieve($opts->{idxdir4anchor}, 'dpnd', 1, $opts->{verbose}, $opts->{show_speed});

    bless $obj;
}

# デストラクタ
sub DESTROY {}

# インデックスファイルから単語を含む文書の検索
sub retrieve_from_dat2 {
    my ($this, $retriever, $reps, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag, $opt) = @_;

    my $start_time = Time::HiRes::time;

    ## 代表表記化／SynGraph により複数個の索引に分割された場合の処理 (かんこう -> 観光 OR 刊行 OR 敢行 OR 感光 を検索する)
    my %idx2qid;
    my @results;
    for (my $i = 0; $i < scalar(@{$reps}); $i++) {
	# rep は構造体
	# rep = {qid, string}
	my $rep = $reps->[$i];

	# $retriever->search($rep, $doc_buff, $add_flag, $position);
	# 戻り値は 0番めがdid, 1番めがfreqの配列の配列 [[did1, freq1], [did2, freq2], ...]
	# $results[$i] = $retriever->search4syngraph($rep, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag);
	$results[$i] = $retriever->search_syngraph_test_for_new_format($rep, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag);
	print scalar(@{$results[$i]}) . " " . $rep->{string} . " OR\n" if ($opt->{verbose});

	if ($this->{verbose}) {
	    print "qid=" . $rep->{qid} . " ";
	    foreach my $d (@{$results[$i]}) {
		print $d->[0] . " ";
	    }
	    print "\n";
	}

	$idx2qid{$i} = $rep->{qid};
    }

    my $ret = $this->merge_search_result(\@results, \%idx2qid);
    
    print scalar(@$ret) . " merged.\n"  if ($opt->{verbose});
    print "----------\n"  if ($opt->{verbose});

    if ($this->{show_speed}) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	printf ("@@@ %.4f sec. doclist retrieving from dat.\n", $conduct_time);
    }

    return $ret;
}








sub calculate_score {
    my ($this, $merged_docs, $alldocs, $did2idx, $retriever, $field_type, $qid2gid, $qid2qtf, $qid2df, $d_length_buff, $q2scores, $did2idx_is_empty, $gid2df, $calculateNearDpnds, $basicNodes, $dpnds) = @_;


    #####################################################################
    # 文書のある位置で、もっともスコアの高い基本ノード, SYNノードを求める
    #####################################################################

    my %did2pos_score = ();
    foreach my $docs (@{$alldocs}) {
	foreach my $doc (@{$docs}) {
	    my $did = $doc->{did};
	    next if (!$did2idx_is_empty && !defined $did2idx->{$did});

	    $did2pos_score{$did} = {} unless (exists($did2pos_score{$did}));

	    foreach my $qid_freq (@{$doc->{qid_freq}}) {
		my $qid = $qid_freq->{qid};

		my $pos = $retriever->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});
		my $score = $retriever->load_score($qid_freq->{fnum}, $qid_freq->{offset_score}, $qid_freq->{nums});

		my $gid = $qid2gid->{$qid};
		my $qtf = $qid2qtf->{$qid};
		for (my $i = 0; $i < scalar(@$pos); $i++) {
		    my $p = $pos->[$i];
		    my $s = $qtf * $score->[$i];

		    # ポジション$pでもっともスコアの高い表現（基本ノード or SYNノード）を取得
		    my $max_score_at_p = $did2pos_score{$did}->{$p};
		    unless (defined $max_score_at_p) {
			$did2pos_score{$did}->{$p}{score} = $s;
			$did2pos_score{$did}->{$p}{gid} = $gid;
			$did2pos_score{$did}->{$p}{qid} = $qid;
		    } else {
			if ($max_score_at_p < $s) {
			    $did2pos_score{$did}->{$p}{score} = $s;
			    $did2pos_score{$did}->{$p}{gid} = $gid;
			    $did2pos_score{$did}->{$p}{qid} = $qid;
			}
		    }
		}
	    }
	}
    }




    ##################
    # スコアを計算する
    ##################

    my $idx = 0;
    my $DIST = 30;
    while (my ($did, $pos2score_gid_qid) = each %did2pos_score) {

	################
	# 近接を計算する
	################
	my %dists = ();
	if ($calculateNearDpnds) {

	    my @poslist = sort {$a <=> $b} keys %{$pos2score_gid_qid};
	    foreach my $dpnd (@$dpnds) {
		my $moto = $dpnd->{moto};
		my $saki = $dpnd->{saki};

		my $prev = undef;
		foreach my $pos (@poslist) {
		    my $qid = $pos2score_gid_qid->{$pos}{qid};
		    my $gid = $pos2score_gid_qid->{$pos}{gid};

		    # print "$pos $qid $gid\n" if ($did == 7079771);

		    if (defined $prev) {
			if (($gid eq $moto || $gid eq $saki) && $gid != $prev->{gid}) {
			    my $dist = $pos - $prev->{pos};

			    # $DIST以内ならば登録
			    if ($dist < $DIST) {
				$dists{"$moto/$saki"} += ($dist / $DIST);
			    }

			    $prev->{gid} = $gid;
			}
			$prev->{qid} = $qid;
			$prev->{pos} = $pos;
		    } else {
			$prev->{pos} = $pos;
			$prev->{gid} = $gid;
			$prev->{qid} = $qid;
		    }
		}
	    }

# 	    my $prev = undef;
# 	    foreach my $pos (sort {$a <=> $b} keys %{$pos2score_gid_qid}) {
# 		my $qid = $pos2score_gid_qid->{$pos}{qid};
# 		my $gid = $pos2score_gid_qid->{$pos}{gid};

# 		print "$pos $qid $gid\n" if ($did == 7079771);


# 		if (defined $prev) {
# 		    if ($gid != $prev->{gid} && (!$basicNodes->{$qid} || !$basicNodes->{$prev->{qid}})) {
# 			my $dist = $pos - $prev->{pos};

# 			# $DIST以内ならば登録
# 			if ($dist < $DIST) {
# 			    $dists{"$prev->{gid}/$gid"} += ($dist / $DIST);
# 			}

# 			$prev->{gid} = $gid;
# 		    }
# 		    $prev->{qid} = $qid;
# 		    $prev->{pos} = $pos;
# 		} else {
# 		    $prev->{pos} = $pos;
# 		    $prev->{gid} = $gid;
# 		    $prev->{qid} = $qid;
# 		}
# 	    }
	}




	# OKAPIスコアを求め、各文書の配列に登録する
	$idx = ($did2idx_is_empty) ? $idx : $did2idx->{$did};
	next if (!defined $idx && !$did2idx_is_empty);


	##############################################################
	# 文書中での$qidの総出現回数(正確にはSYNGRAPHのスコア)を求める
	##############################################################

	my %total_scores;
	while (my ($pos, $score_gid_qid) = each(%{$pos2score_gid_qid})) {
	    $total_scores{$score_gid_qid->{qid}} += $score_gid_qid->{score};
	}

	my $dlength = $d_length_buff->{$did};
	# 文書長がバッファになければロード
	unless (defined($dlength)) {
	    foreach my $db (@{$this->{DOC_LENGTH_DBs}}) {
		# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
		if ($this->{dlengthdb_hash}) {
		    $dlength = $db->{$did};
		    if (defined $dlength) {
			$d_length_buff->{$did} = $dlength;
			last;
		    }
		}
		else {
		    $dlength = $db->{$did};
		    if (defined($dlength)) {
			$d_length_buff->{$did} = $dlength;
			last;
		    }
		}
	    }
	}



	while (my ($qid, $score) = each(%total_scores)) {
	    my $df = $qid2df->{$qid};
	    my $qtf = $qid2qtf->{$qid};

	    my $okapi_score;
	    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
	    if ($df == -1) {
		$okapi_score = 0;
	    }
	    else {
		# my $tff = 1 * (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
		my $tff = 1 * (3 * $score) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score);
		my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
		$okapi_score = $qtf * $tff * $idf;
	    }

	    $this->{verbose} = 1 if ($did =~ /78922624/ || $did =~ /58400434/);
	    print "did=$did qid=$qid tf=$score df=$df qtf=$qtf length=$dlength score=$score okapi=$okapi_score\n" if ($this->{verbose});
	    $this->{verbose} = 0;

	    $q2scores->[$idx]{$field_type}{$qid} = {tf => $score, qtf => $qtf, df => $df, dlength => $dlength, score => $okapi_score} if $this->{logging_query_score};

	    $merged_docs->[$idx]{$field_type}{$qid} = $okapi_score;
	    $merged_docs->[$idx]{'score_' . $field_type} += $okapi_score;
	}


	######################
	# 近接スコアを計算する
	######################

	if ($calculateNearDpnds) {
	    my $okapi_score = 0;
	    foreach my $gid (keys %dists) {
		my $df = $gid2df->{$gid};
		if ($df == -1 || !defined $df) {
		    $okapi_score = 0;
		}
		else {
		    my $score = $dists{$gid};
		    my $tff = 1 * (3 * $score) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score);
		    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
		    $okapi_score = $tff * $idf;

		    $merged_docs->[$idx]{'score_dist'} += $okapi_score;
		}
	    }
	}


	if ($did2idx_is_empty) {
	    $merged_docs->[$idx]{did} = $did;
	    $did2idx->{$did} = $idx++;
	}
    }
}





# 文書のスコアリング
sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $alldocs_word_anchor, $alldocs_dpnd_anchor, $qid2df, $cal_method, $qid2qtf, $dpnd_map, $qid2gid, $dpnd_on, $dist_on, $DIST, $MIN_DLENGTH, $gid2weight, $results, $gid2df, $basicNodes, $dpnds) = @_;

    my $start_time = Time::HiRes::time;

    my $pos = 0;
    my @merged_docs = ();
    my %d_length_buff = ();
    my %did2pos_score = ();
    my %gid2near_score = ();
    my @q2scores = ();

#     # 検索キーワードごとに区切る
#     foreach my $docs_word (@{$alldocs_words}) {
# 	foreach my $doc (@{$docs_word}) {
# 	    my $did = $doc->{did};

# 	    # 初期化
# 	    $did2pos_score{$did} = {} unless (exists($did2pos_score{$did}));

# 	    my %qid2poslist = ();
# 	    foreach my $qid_freq (@{$doc->{qid_freq}}) {
# 		my $qid = $qid_freq->{qid};
# 		my $dlength = $d_length_buff{$did};

# 		# 文書長がバッファになければロード
# 		unless (defined($dlength)) {
# 		    foreach my $db (@{$this->{DOC_LENGTH_DBs}}) {
# 			# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
# 			if ($this->{dlengthdb_hash}) {
# 			    $dlength = $db->{$did};
# 			    if (defined $dlength) {
# 				$d_length_buff{$did} = $dlength;
# 				last;
# 			    }
# 			}
# 			else {
# 			    $dlength = $db->{$did};
# 			    if (defined($dlength)) {
# 				$d_length_buff{$did} = $dlength;
# 				last;
# 			    }
# 			}
# 		    }
# 		}

# 		my $pos = $this->{word_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums}, {verbose => $this->{verbose}});
# 		my $score = $this->{word_retriever}->load_score($qid_freq->{fnum}, $qid_freq->{offset_score}, $qid_freq->{nums});

# 		$qid2poslist{$qid} = $pos;

# 		my $qtf = $qid2qtf->{$qid};
# 		for (my $i = 0; $i < scalar(@$pos); $i++) {
# 		    my $p = $pos->[$i];
# 		    my $s = $score->[$i] * $qtf;
# 		    my $gid = $qid2gid->{$qid};
# 		    print "* did=$did pos=$p qid=$qid gid=$gid qtf=$qtf score=$score->[$i] qtf * score = $s\n"if ($this->{verbose});

# 		    # ポジション$pでもっともスコアの高い表現（基本ノード or SYNノード）を取得
#  		    my $max_score_at_p = $did2pos_score{$did}->{$p}{score};
#  		    unless (defined $max_score_at_p) {
#  			$did2pos_score{$did}->{$p}{score} = $s;
#  			$did2pos_score{$did}->{$p}{gid} = $qid2gid->{$qid};
#  			$did2pos_score{$did}->{$p}{qid} = $qid;
# 			$did2pos_score{$did}->{$p}{qtf} = $qtf;
#  		    } else {
# 			if ($max_score_at_p < $s) {
# 			    $did2pos_score{$did}->{$p}{score} = $s;
# 			    $did2pos_score{$did}->{$p}{gid} = $qid2gid->{$qid};
# 			    $did2pos_score{$did}->{$p}{qid} = $qid;
# 			    $did2pos_score{$did}->{$p}{qtf} = $qtf;
# 			}
#  		    }
#  		}
# 		print "-----\n" if ($this->{verbose});
# 	    }

# 	    # nearの計算
# #  	    foreach my $qid (keys %$dpnd_map) {
# #  		foreach my $e (@{$dpnd_map->{$qid}}) {
# #  		    my $dpnd_qid = $e->{dpnd_qid};
# #  		    my $kakarisaki_qid = $e->{kakarisaki_qid};
# #  		    my $dlength = $d_length_buff{$did};
# #  		    my $df = $qid2df->{$dpnd_qid};
# #  		    next if ($df < 0);

# #  		    my $dist = $this->get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
# # 		    my $gid = $qid2gid->{$dpnd_qid};

# # 		    # print "did=$did qid=$dpnd_qid dist=$dist\n";
# #  		    if ($dist > $DIST || $dist < 0) {
# # 			$gid2near_score{$did}->{$gid} = 0 unless (defined $gid2near_score{$gid});
# #  		    } else {
# #  			my $d = ($DIST - $dist) / $DIST;
# #  			my $qtf = $qid2qtf->{$dpnd_qid};

# # # 			my $tff = (3 * $d) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $d);
# # 			my $tff = (2 * $d) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $d); # k1 = 1, b = 0.6, k3 = 0
# #  			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
# #  			my $score = $qtf * $tff * $idf;

# # 			unless (defined $gid2near_score{$gid}) {
# # 			    $gid2near_score{$did}->{$gid} = $score;
# # 			} else {
# # 			    $gid2near_score{$did}->{$gid} = $score if ($score > $gid2near_score{$gid});
# # 			}
# #  		    }
# #  		}
# # 	    }
# 	}
#     }


#     my $i = 0;
#     my %did2pos = ();
#     while (my ($did, $pos2score) = each(%did2pos_score)) {
# 	my %scores;
# 	while (my ($pos, $score_gid_qid) = each(%{$pos2score})) {
# 	    $scores{$score_gid_qid->{qid}} += $score_gid_qid->{score};
# 	}

# 	my $okapi_score;
# 	foreach my $qid (keys %scores) {
# 	    my $score = $scores{$qid};
# 	    my $df = $qid2df->{$qid};
# 	    my $weight = 1; #$qid2weight->{$qid};
# 	    my $dlength = $d_length_buff{$did};
# #	    my $qtf = $qid2qtf->{$qid};

# 	    # 関数化するよりも高速
# # 	    my $tff = 3 * $score / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score);
# 	    my $tff = $weight * (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
#  	    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
# 	    my $sub_okapi = $tff * $idf;
#  	    $okapi_score += $sub_okapi;

#  	    print "did=$did qid=$qid score=$score df=$df length=$dlength score=$okapi_score\n" if ($this->{verbose});
# 	    $q2scores[$i]->{word}{$qid} = {tf => $score, weight => $weight, df => $df, dlength => $dlength, score => $sub_okapi};
# 	}
# 	$merged_docs[$i] = {did => $did, score_total => $okapi_score, score_word => $okapi_score};
# 	$did2pos{$did} = $i;
# 	$i++;
#     }



    my %did2idx = ();
    my $did2idx_is_empty = 1;
    my $calculateNearDpnds = 1;

    $this->calculate_score(\@merged_docs, $alldocs_words, \%did2idx, $this->{word_retriever}, 'word', $qid2gid, $qid2qtf, $qid2df, \%d_length_buff, \@q2scores, $did2idx_is_empty, $gid2df, $calculateNearDpnds, $basicNodes, $dpnds);
    $did2idx_is_empty = 0;
    $this->calculate_score(\@merged_docs, $alldocs_dpnds, \%did2idx, $this->{dpnd_retriever}, 'dpnd', $qid2gid, $qid2qtf, $qid2df, \%d_length_buff, \@q2scores, $did2idx_is_empty);
    $this->calculate_score(\@merged_docs, $alldocs_word_anchor, \%did2idx, $this->{word_retriever4anchor}, 'word_anchor', $qid2gid, $qid2qtf, $qid2df, \%d_length_buff, \@q2scores, $did2idx_is_empty);
    $this->calculate_score(\@merged_docs, $alldocs_dpnd_anchor, \%did2idx, $this->{dpnd_retriever4anchor}, 'dpnd_anchor', $qid2gid, $qid2qtf, $qid2df, \%d_length_buff, \@q2scores, $did2idx_is_empty);

    my @result;
    for (my $i = 0; $i < @merged_docs; $i++) {
	my $e = $merged_docs[$i];

	my $score = $e->{score_word};
	$score += $e->{score_dpnd} if ($dpnd_on);
	$score += $e->{score_dist} if ($dist_on);
	$score += ($e->{score_word_anchor} + $e->{score_dpnd_anchor});

	if ($this->{verbose}) {
	    printf ("did=%09d w=%.3f d=%.3f n=%.3f anchor_w=%.3f anchor_d=%.3f total=%.3f\n", $e->{did}, $e->{score_word}, $e->{score_dpnd}, $e->{score_dist}, $e->{score_word_anchor}, $e->{score_dpnd_anchor}, $score);
	}

	push(@result, {did => $e->{did}, score_total => $score});

	if ($this->{score_verbose}) {
	    $result[-1]->{score_word} = $e->{score_word};
	    $result[-1]->{score_dpnd} = $e->{score_dpnd};
	    $result[-1]->{score_dist} = $e->{score_dist};
	    $result[-1]->{score_word_anchor} = $e->{score_word_anchor};
	    $result[-1]->{score_dpnd_anchor} = $e->{score_dpnd_anchor};
	}
    }
    print "-----\n"if ($this->{verbose});

    @merged_docs = sort {$b->{score_total} <=> $a->{score_total}} @result;

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doc_list merging.\n", $conduct_time);
    }

    return \@merged_docs;
}

sub merge_docs2 {
    my ($this, $alldocs_words, $alldocs_dpnds, $qid2df, $cal_method, $qid2qtf, $dpnd_map, $qid2gid) = @_;

    my $start_time = Time::HiRes::time;

    my $pos = 0;
    my %did2pos = ();
    my @merged_docs = ();
    my %d_length_buff = ();
    my %did2pos_score = ();
    my %gid2near_score = ();
    # 検索キーワードごとに区切る
    foreach my $docs_word (@{$alldocs_words}) {
	foreach my $doc (@{$docs_word}) {
	    my $did = $doc->{did};

	    # 初期化
	    $did2pos_score{$did} = {} unless (exists($did2pos_score{$did}));

	    my %qid2poslist = ();
	    foreach my $qid_freq (@{$doc->{qid_freq}}) {
		my $tf = $qid_freq->{freq};
		my $qid = $qid_freq->{qid};
		my $df = $qid2df->{$qid};
		my $qtf = $qid2qtf->{$qid};
		my $dlength = $d_length_buff{$did};

		unless (defined($dlength)) {
		    foreach my $db (@{$this->{DOC_LENGTH_DBs}}) {
			# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
			if ($this->{dlengthdb_hash}) {
			    $dlength = $db->{$did};
			    if (defined $dlength) {
				$d_length_buff{$did} = $dlength;
				last;
			    }
			}
			else {
			    $dlength = $db->{$did};
			    if (defined($dlength)) {
				$d_length_buff{$did} = $dlength;
				last;
			    }
			}
		    }
		}

		# 関数化するよりも高速
		my $tff = 3 * $tf / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
		my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));

		my $pos = $this->{word_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});

		my $size = scalar(@$pos);
		my $scr = $qtf * $tff * $idf / $size;
		$qid2poslist{$qid} = $pos;

		print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$scr * size=$size\n" if ($this->{verbose});

		foreach my $p (@$pos) {
		    my $score = $did2pos_score{$did}->{$p};
		    unless (defined $score) {
			$did2pos_score{$did}->{$p} = $scr;
		    } else {
			$did2pos_score{$did}->{$p} = $scr if ($score < $scr);
		    }
		}
	    }

 	    foreach my $qid (keys %$dpnd_map) {
 		foreach my $e (@{$dpnd_map->{$qid}}) {
 		    my $dpnd_qid = $e->{dpnd_qid};
 		    my $kakarisaki_qid = $e->{kakarisaki_qid};
 		    my $dlength = $d_length_buff{$did};
 		    my $df = $qid2df->{$dpnd_qid};
 		    next if ($df < 0);

 		    my $dist = $this->get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
		    my $gid = $qid2gid->{$dpnd_qid};

		    # print "did=$did qid=$dpnd_qid dist=$dist\n";
 		    if ($dist > 30) {
			$gid2near_score{$did}->{$gid} = 0 unless (defined $gid2near_score{$gid});
 		    } else {
 			my $tf = (30 - $dist) / 30;
 			my $qtf = $qid2qtf->{$dpnd_qid};

 			my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
 			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
 			my $score = $qtf * $tff * $idf;

			unless (defined $gid2near_score{$gid}) {
			    $gid2near_score{$did}->{$gid} = $score;
			} else {
			    $gid2near_score{$did}->{$gid} = $score if ($score > $gid2near_score{$gid});
			}
			# $merged_docs[$i]->{near_score}{$dpnd_qid} = $score;
 		    }
 		}
	    }
	}
    }


    my $i = 0;
    my $did2pos = ();
    while (my ($did, $pos2score) = each(%did2pos_score)) {
	my $sum;
	while (my ($pos, $score) = each(%{$pos2score})) {
	    $sum += $score;
	}
	$merged_docs[$i] = {did => $did, score_total => $sum};
	$did2pos{$did} = $i;
	$i++;
    }

    unless (defined($cal_method)) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	if ($this->{show_speed}) {
	    printf ("@@@ %.4f sec. doclist merging.\n", $conduct_time);
	}
	return \@merged_docs;
    }

    my %did2gid_dpnd = ();
    my %did2pos_score = ();
    foreach my $docs_dpnd (@{$alldocs_dpnds}) {
	foreach my $doc (@{$docs_dpnd}) {
	    my $did = $doc->{did};
	    my $i = $did2pos{$did};
	    if (defined $i) {
		unless (exists($did2pos_score{$did})) {
		    $did2pos_score{$did} = {};
		}

		foreach my $qid_freq (@{$doc->{qid_freq}}) {
		    my $tf = $qid_freq->{freq};
		    my $qid = $qid_freq->{qid};
		    my $df = $qid2df->{$qid};
		    my $qtf = $qid2qtf->{$qid};
		    my $dlength = $d_length_buff{$did};

		    my ($pos, $scr);
		    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
		    if ($df == -1) {
			$scr = 0;
		    }
		    else {
			my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));

			$pos = $this->{dpnd_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});

			my $size = scalar(@$pos);
			$scr = $qtf * $tff * $idf / $size;
			$scr *= $this->{WEIGHT_DPND_SCORE};

			$did2gid_dpnd{$did}->{$qid2gid->{$qid}} = 1;
		    }

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$scr\n" if ($this->{store_verbose});

		    foreach my $p (@$pos) {
			my $score = $did2pos_score{$did}->{$p};
			unless (defined $score) {
			    $did2pos_score{$did}->{$p} = $scr;
			} else {
			    $did2pos_score{$did}->{$p} = $scr if ($score < $scr);
			}
		    }
		}
	    }
	}
    }
    
#     while (my ($did, $pos2score) = each(%did2pos_score)) {
# 	my $i = $did2pos{$did};
# 	my $sum_of_dpnd_score;
# 	while (my ($pos, $score) = each(%{$pos2score})) {
# 	    $sum_of_dpnd_score += $score;
# 	}

# 	print "did=$did dpnd=$sum_of_dpnd_score\n";
# 	$merged_docs[$i]->{score} += $sum_of_dpnd_score;

# 	foreach my $gid (keys %{$gid2near_score{$did}}) {
# 	    print "did=$did gid=$gid \n";
# 	    next if (defined $did2gid_dpnd{$did}->{$gid});
# 	}
#     }

    while (my ($did, $gid2near) = each %gid2near_score) {
	my $sum_of_dpnd_score;
	foreach my $pos (keys %{$did2pos_score{$did}}) {
	    $sum_of_dpnd_score += $did2pos_score{$did}{$pos};
	}

#	print "did=$did dpnd=$sum_of_dpnd_score\n";

	my $i = $did2pos{$did};
	$merged_docs[$i]->{score_total} += $sum_of_dpnd_score;

 	foreach my $gid (keys %{$gid2near}) {
 	    next if (defined $did2gid_dpnd{$did}->{$gid});

	    $merged_docs[$i]->{score_total} += $gid2near->{$gid};
#	    print "did=$did gid=$gid near=$gid2near->{$gid}\n";
	}
    }

    @merged_docs = sort {$b->{score_total} <=> $a->{score_total}} @merged_docs;

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doc_list merging.\n", $conduct_time);
    }

    return \@merged_docs;
}

# 配列の配列を受け取り OR をとる (配列の配列をマージして単一の配列にする)
sub merge_search_result {
    my ($this, $docs_list, $idx2qid) = @_;

    my $start_time = Time::HiRes::time;

    my $serialized_docs = [];
    my $pos = 0;
    my %did2pos = ();

    for(my $i = 0; $i < scalar(@{$docs_list}); $i++) {
	my $qid = $idx2qid->{$i};
	foreach my $d (@{$docs_list->[$i]}) {
	    next unless (defined($d)); # 本来なら空はないはず

	    my $did = $d->[0];
	    my $fnum = $d->[1];
	    my $size = $d->[2];
	    my $offset_pos = $d->[3];
	    my $offset_score = $d->[4];

	    if ($this->{verbose}) {
		print "num_of_positions = $size\n";
		print "index_file_ID    = $fnum\n";
		print "offset_of_offset = $offset_pos\n";
		print "offset_of_score  = $offset_score\n";
		print "-----\n";
	    }

	    if (exists($did2pos{$did})) {
		my $j = $did2pos{$did};
		push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, fnum => $fnum, nums => $size, offset => $offset_pos, offset_score => $offset_score});
	    } else {
		$serialized_docs->[$pos] = {did => $did, qid_freq => [{qid => $qid, fnum => $fnum, nums => $size, offset => $offset_pos, offset_score => $offset_score}]};

		$did2pos{$did} = $pos;
		$pos++;
	    }
	}
    }
    # ★このソートは無駄★
    # 上の処理でpushする際に適切な位置に挿入できればよい
    @{$serialized_docs} = sort {$a->{did} <=> $b->{did}} @{$serialized_docs};

    if ($this->{verbose}) {
	foreach my $e (@{$serialized_docs->[0]{qid_freq}}) {
	    print "$e->{qid}\n";
	}
	print "--------------------\n";
    }


    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doclist serializing (2).\n", $conduct_time);
    }

    return $serialized_docs;
}

sub merge_search_result2 {
    my ($this, $docs_list, $idx2qid) = @_;

    my $start_time = Time::HiRes::time;

    my $serialized_docs = [];
    my $pos = 0;
    my %did2pos = ();
    for(my $i = 0; $i < scalar(@{$docs_list}); $i++) {
	my $qid = $idx2qid->{$i};
	foreach my $d (@{$docs_list->[$i]}) {
	    next unless (defined($d)); # 本来なら空はないはず

	    my $did = $d->[0];
	    my $freq = $d->[1];
	    my $fnum = $d->[2];
	    my $offset = $d->[3];
	    my $size = $d->[4];
	    if (exists($did2pos{$did})) {
		my $j = $did2pos{$did};
		if (defined($offset)) {
		    push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, freq => $freq, fnum => $fnum, offset => $offset, nums => $size});
		} else {
		    push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, freq => $freq});
		}
	    } else {
		if (defined($offset)) {
		    $serialized_docs->[$pos] = {did => $did, qid_freq => [{qid => $qid, freq => $freq, fnum => $fnum, offset => $offset, nums => $size}]};
		} else {
		    $serialized_docs->[$pos] = {did => $did, qid_freq => [{qid => $qid, freq => $freq}]};
		}

		$did2pos{$did} = $pos;
		$pos++;
	    }
	}
    }
    @{$serialized_docs} = sort {$a->{did} <=> $b->{did}} @{$serialized_docs};

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doclist serializing (2).\n", $conduct_time);
    }

    return $serialized_docs;
}

# 近接条件の適用
sub filter_by_NEAR_constraint2 {
    my ($this, $docs, $near, $sentence_flag) = @_;

    return $docs if ($near < 0);

    # 初期化 & 空リストのチェック
    my @results = ();
    my $flag = 0;
    for (my $i = 0; $i < scalar(@{$docs}); $i++) {
	$flag = 1 unless (defined($docs->[$i]));
	$flag = 2 if (scalar(@{$docs->[$i]}) < 1);

	$results[$i] = [];
    }
    return \@results if ($flag > 0 || scalar(@{$docs}) < 1);

    # 単語の（クエリ中での）出現順序でソート
    @{$docs} = sort{$a->[0]{qid_freq}[0]->{qid} <=> $b->[0]{qid_freq}[0]->{qid}} @{$docs};

    for (my $d = 0; $d < scalar(@{$docs->[0]}); $d++) {
	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@{$docs}); $q++) {
	    foreach my $p (@{$docs->[$q][$d]->{pos}}) {
		push(@{$poslist[$q]}, $p);
	    }
	}

	while (scalar(@{$poslist[0]}) > 0) {
	    my $flag = 0;
	    my $pos = shift(@{$poslist[0]}); # クエリ中の先頭の単語の出現位置
	    my $distance_history = 0; # 各単語間の距離の総和
	    for (my $q = 1; $q < scalar(@poslist); $q++) {
		while (1) {
		    # クエリ中の単語の出現位置リストが空なら終了
		    if (scalar(@{$poslist[$q]}) < 1) {
			$flag = 1;
			last;
		    }

		    if ($sentence_flag > 0) {
			if ($pos <= $poslist[$q]->[0] && $poslist[$q]->[0] < $pos + $near - $distance_history) {
			    $distance_history += ($poslist[$q]->[0] - $pos);
			    $flag = 0;
			    last;
			} elsif ($poslist[$q]->[0] < $pos) {
			    shift(@{$poslist[$q]});
			} else {
			    $flag = 1;
			    last;
			}
		    } else {
#			print "$pos < $poslist[$q]->[0] && $poslist[$q]->[0] < ", ($pos + $near - $distance_history) . "\n";
			if ($pos < $poslist[$q]->[0] && $poslist[$q]->[0] < $pos + $near - $distance_history) {
			    $distance_history += ($poslist[$q]->[0] - $pos);
			    $flag = 0;
			    last;
			} elsif ($poslist[$q]->[0] < $pos) {
			    shift(@{$poslist[$q]});
			} else {
			    $flag = 1;
			    last;
			}
		    }
		}

		last if ($flag > 0);
		$pos = $poslist[$q]->[0];
	    }

	    if ($flag == 0) {
		for (my $q = 0; $q < scalar(@{$docs}); $q++) {
		    push(@{$results[$q]}, $docs->[$q][$d]);
		}
		last;
	    }
	}
    }

    return \@results;
}

1;
