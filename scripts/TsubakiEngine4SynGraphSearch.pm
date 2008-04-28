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

# $alldocs_words, $alldocs_dpnds 構造体の中身
# $VAR1 = [
#           [
#             {
#               'did' => 130903,
#               'qid_freq' => [
#                               {
#                                 'qid' => 8,
#                                 'fnum' => 0,
#                                 'offset_score' => 231088602,
#                                 'nums' => 1,
#                                 'offset' => 231074070
#                               },
#                               {
#                                 'qid' => 9,
#                                 'fnum' => 0,
#                                 'offset_score' => 9731880,
#                                 'nums' => 1,
#                                 'offset' => 9717348
#                               },
#                               {
#                                 'qid' => 11,
#                                 'fnum' => 0,
#                                 'offset_score' => 45112430,
#                                 'nums' => 1,
#                                 'offset' => 45095698
#                               }
#                             ]
#             },

# 文書のスコアリング

#  	    foreach my $qid (keys %$dpnd_map) {
#  		foreach my $e (@{$dpnd_map->{$qid}}) {
#  		    my $dpnd_qid = $e->{dpnd_qid};
#  		    my $kakarisaki_qid = $e->{kakarisaki_qid};
#  		    my $dlength = $d_length_buff{$did};
#  		    my $df = $qid2df->{$dpnd_qid};
#  		    next if ($df < 0);

#  		    my $dist = $this->get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
# 		    my $gid = $qid2gid->{$dpnd_qid};

# 		    # print "did=$did qid=$dpnd_qid dist=$dist\n";
#  		    if ($dist > 30) {
# 			$gid2near_score{$did}->{$gid} = 0 unless (defined $gid2near_score{$gid});
#  		    } else {
#  			my $d = (30 - $dist) / 30;
#  			my $qtf = $qid2qtf->{$dpnd_qid};

# # 			my $tff = (3 * $d) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $d);
# 			my $tff = (2 * $d) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $d); # k1 = 1, b = 0.6, k3 = 0
#  			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
#  			my $score = $qtf * $tff * $idf;

# 			unless (defined $gid2near_score{$gid}) {
# 			    $gid2near_score{$did}->{$gid} = $score;
# 			} else {
# 			    $gid2near_score{$did}->{$gid} = $score if ($score > $gid2near_score{$gid});
# 			}
#  		    }
#  		}
# 	    }


sub get_scores {
    my ($this, $retriever, $docs, $qid2qtf, $qid2gid) = @_;

    my %did2pos_score = ();

    # 検索キーワードごとに区切る
    foreach my $docs_word (@$docs) {
	foreach my $doc (@{$docs_word}) {
	    my $did = $doc->{did};
	    $did2pos_score{$did} = {} unless (exists($did2pos_score{$did}));

	    # $did文書に含まれる各クエリ$qidについて
	    foreach my $qid_freq (@{$doc->{qid_freq}}) {
		my $qid = $qid_freq->{qid};
		my $qtf = $qid2qtf->{$qid};

		# $qidの出現位置を取得、各出現位置でのスコアを取得
		my $poss = $retriever->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums}, {verbose => $this->{verbose}});
		my $scores = $retriever->load_score($qid_freq->{fnum}, $qid_freq->{offset_score}, $qid_freq->{nums});

		# SYNノードごとに出現箇所でのスコアを計算
		for (my $i = 0; $i < scalar(@$poss); $i++) {
		    my $pos = $poss->[$i];
		    my $score = $scores->[$i] * $qtf;
		    my $gid = $qid2gid->{$qid};
		    print "* did=$did pos=$pos qid=$qid gid=$gid qtf=$qtf score=$scores->[$i] qtf * score = $score\n" if ($this->{verbose});

		    # 同義表現グループ内でスコアが最大のSYNノードがその出現位置に現れているとする
 		    my $max_score_at_p = $did2pos_score{$did}->{$gid}{$pos}{score};
 		    unless (defined $max_score_at_p) {
 			$did2pos_score{$did}->{$gid}{$pos}{score} = $score;
 			$did2pos_score{$did}->{$gid}{$pos}{qid} = $qid;
			$did2pos_score{$did}->{$gid}{$pos}{qtf} = $qtf;
 		    } else {
			if ($max_score_at_p < $score) {
			    $did2pos_score{$did}->{$gid}{$pos}{score} = $score;
			    $did2pos_score{$did}->{$gid}{$pos}{qid} = $qid;
			    $did2pos_score{$did}->{$gid}{$pos}{qtf} = $qtf;
			}
 		    }
 		}
		print "-----\n" if ($this->{verbose});
	    }
	}
    }

    return \%did2pos_score;
}

sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $qid2df, $cal_method, $qid2qtf, $dpnd_map, $qid2gid, $dpnd_on, $dist_on, $DIST, $MIN_DLENGTH, $gid2weight) = @_;
    my $start_time = Time::HiRes::time;

    my %gid2df = ();
    foreach my $qid (keys %$qid2gid) {
	my $df = $qid2df->{$qid};
	my $gid = $qid2gid->{$qid};
	$gid2df{$gid} = $df;

	if ($this->{verbose}) {
	    print "gid=$gid qid=$qid gdf=$df\n";
	}
    }

    my $did2pos_score_of_word = $this->get_scores($this->{word_retriever}, $alldocs_words, $qid2qtf, $qid2gid);
    my $did2pos_score_of_dpnd = $this->get_scores($this->{dpnd_retriever}, $alldocs_dpnds, $qid2qtf, $qid2gid);

    # SYNノードから求める文書のスコアを計算
    my $i = 0;
    my @merged_docs = ();
    my @q2scores = ();
    while (my ($did, $gidinfo) = each(%$did2pos_score_of_word)) {

	# 文書長の取得
	my $dlength = 0;
	foreach my $db (@{$this->{DOC_LENGTH_DBs}}) {
	    # 小規模なテスト用にdlengthのDBをハッシュでもつオプション
	    if ($this->{dlengthdb_hash}) {
		$dlength = $db->{$did};
		last if (defined $dlength);
	    } else {
		$dlength = $db->{$did};
		last if (defined($dlength));
	    }
	}

	# 同義表現グループごとに文書$didでのスコアの総和を計算(WORD)
	my %gid2score = ();
	while (my ($gid, $pos2info) = each(%{$gidinfo})) {
	    while (my ($pos, $info) = each(%{$pos2info})) {
		$gid2score{$gid} += $info->{score};
	    }
	}


	# 同義表現グループごとに文書$didでのスコアの総和を計算(DPND)
	my %gid2score_dpnd = ();
	if ($dpnd_on) {
	    my $gidinfo_dpnd = $did2pos_score_of_dpnd->{$did};
	    if ($gidinfo_dpnd) {
		while (my ($gid, $pos2info) = each(%{$gidinfo_dpnd})) {
		    while (my ($pos, $info) = each(%{$pos2info})) {
			$gid2score_dpnd{$gid} += $info->{score};
		    }
		}
	    }
	}


	##########################
	# 単語・句によるスコア計算
	##########################

	# スコアをもとにOKAPIを計算(WORD)
	my $okapi_total = 0;
	while (my ($gid, $score) = each(%gid2score)) {
	    my $weight = $gid2weight->{$gid};
	    my $gdf = $gid2df{$gid};
 	    my $tff = $weight * (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
  	    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $gdf + 0.5) / ($gdf + 0.5));
 	    my $okapi = $tff * $idf;
	    $okapi_total += ($weight * $okapi);

  	    print "did=$did gid=$gid score=$score df=$gdf length=$dlength okapi_score=$okapi\n" if ($this->{verbose});
 	    $q2scores[$i]->{word}{$gid} = {tf => $score, weight => $weight, df => $gdf, score => $okapi, tff => $tff, idf => $idf};
	}
	$merged_docs[$i]->{score_word} = $okapi_total;


	##########################
	# 係り受けによるスコア計算
	##########################

	# スコアをもとにOKAPIを計算(DPND)
	my $okapi_total = 0;
	while (my ($gid, $score) = each(%gid2score_dpnd)) {
	    my $weight = $gid2weight->{$gid};
	    my $gdf = $gid2df{$gid};
 	    my $tff = $weight * (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
  	    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $gdf + 0.5) / ($gdf + 0.5));
 	    my $okapi = $tff * $idf;
	    $okapi_total += ($weight * $okapi);

  	    print "did=$did gid=$gid score=$score df=$gdf length=$dlength okapi_score=$okapi\n" if ($this->{verbose});
 	    $q2scores[$i]->{dpnd}{$gid} = {tf => $score, weight => $weight, df => $gdf, score => $okapi, tff => $tff, idf => $idf};
	}

	$merged_docs[$i]->{score_dpnd} = $okapi_total;
	$merged_docs[$i]->{score_total} = $merged_docs[$i]->{score_word};
	$merged_docs[$i]->{score_total} += $merged_docs[$i]->{score_dpnd} if ($dpnd_on);
	$merged_docs[$i]->{dlength} = $dlength;
	$merged_docs[$i]->{q2score} = $q2scores[$i];
	$merged_docs[$i++]->{did} = $did;
    }

    @merged_docs = sort {$b->{score_total} <=> $a->{score_total}} @merged_docs;
    return \@merged_docs;

# 	my %scores;
# 	while (my ($pos, $score_gid_qid) = each(%{$pos2score})) {
# 	    $scores{$score_gid_qid->{gid}} += $score_gid_qid->{score};
# 	}

# 	my $okapi_score;
# 	foreach my $gid (keys %scores) {
# 	    my $score = $scores{$gid} / 1000;
# 	    my $df = $gid2df{$gid};
# 	    my $weight = $gid2weight->{$gid};
# 	    my $dlength = $d_length_buff{$did};
# #	    my $qtf = $gid2qtf->{$gid};

# 	    # 関数化するよりも高速
# # 	    my $tff = 3 * $score / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score);
# 	    my $tff = $weight * (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
#  	    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
# 	    my $sub_okapi = $tff * $idf;
#  	    $okapi_score += $sub_okapi;

#  	    print "did=$did gid=$gid score=$score df=$df length=$dlength score=$okapi_score\n" if ($this->{verbose});
# 	    # $q2scores[$i]->{word}{$gid} = {tf => $score, weight => $weight, df => $df, dlength => $dlength, score => $sub_okapi};
# 	    $q2scores[$i]->{word}{$gid} = {tf => $score, weight => $weight, df => $df, dlength => $dlength, score => $sub_okapi, tff => $tff, idf => $idf, qtf => $qid2qtf->{$gid}};
# 	}
# 	$merged_docs[$i] = {did => $did, score_total => $okapi_score};
# 	$did2pos{$did} = $i;
# 	$i++;
#     }

#     unless (defined($cal_method)) {
# 	my $finish_time = Time::HiRes::time;
# 	my $conduct_time = $finish_time - $start_time;
# 	if ($this->{show_speed}) {
# 	    printf ("@@@ %.4f sec. doclist merging.\n", $conduct_time);
# 	}
# 	return \@merged_docs;
#     }

#     my %did2gid_dpnd = ();
#     my %did2pos_score = ();
#     foreach my $docs_dpnd (@{$alldocs_dpnds}) {
# 	foreach my $doc (@{$docs_dpnd}) {
# 	    my $did = $doc->{did};
# 	    my $i = $did2pos{$did};
# 	    if (defined $i) {
# 		unless (exists($did2pos_score{$did})) {
# 		    $did2pos_score{$did} = {};
# 		}

# 		foreach my $qid_freq (@{$doc->{qid_freq}}) {
# 		    my $qid = $qid_freq->{qid};

# 		    my $pos = $this->{dpnd_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});
# 		    my $score = $this->{dpnd_retriever}->load_score($qid_freq->{fnum}, $qid_freq->{offset_score}, $qid_freq->{nums});

# 		    $did2gid_dpnd{$did}->{$qid2gid->{$qid}} = 1;
# 		    my $gid = $qid2gid->{$qid};
# 		    my $qtf = $qid2qtf->{$qid};
# 		    for (my $i = 0; $i < scalar(@$pos); $i++) {
# 			my $p = $pos->[$i];
# 			my $s = $qtf * $score->[$i];

# 			my $max_score_at_p = $did2pos_score{$did}->{$p};
# 			unless (defined $max_score_at_p) {
# 			    $did2pos_score{$did}->{$p}{score} = $s;
# 			    $did2pos_score{$did}->{$p}{gid} = $gid;
# 			    $did2pos_score{$did}->{$p}{qid} = $qid;
# 			} else {
# 			    if ($max_score_at_p < $s) {
# 				$did2pos_score{$did}->{$p}{score} = $s;
# 				$did2pos_score{$did}->{$p}{gid} = $gid;
# 				$did2pos_score{$did}->{$p}{qid} = $qid;
# 			    }
# 			}
# 		    }
# 		}
# 	    }
# 	}
#     }

#     while (my ($did, $gid2near) = each %gid2near_score) {
# 	my %sum_of_dpnd_score;
# 	foreach my $pos (keys %{$did2pos_score{$did}}) {
# 	    my $qid = $did2pos_score{$did}->{$pos}{qid};
# 	    $sum_of_dpnd_score{$qid} += $did2pos_score{$did}->{$pos}{score};
# 	}

# 	my $i = $did2pos{$did};

# 	$merged_docs[$i]->{did} = $did;
# 	$merged_docs[$i]->{score_word} = $merged_docs[$i]->{score_total};

# 	my $okapi_score;
# 	foreach my $qid (keys %sum_of_dpnd_score) {
# 	    my $score = $sum_of_dpnd_score{$qid};
# 	    my $df = $qid2df->{$qid};
# 	    my $dlength = $d_length_buff{$did};

# 	    # 関数化するよりも高速
# 	    my $tff = (2 * $score) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score); # k1 = 1, b = 0.6, k3 = 0
# #	    my $tff = 3 * $score / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $score);
# 	    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
# 	    my $sub_okapi = $tff * $idf * $this->{WEIGHT_DPND_SCORE};
# 	    $okapi_score += $sub_okapi;
# 	    print "did=$did qid=$qid score=$score df=$df length=$dlength score=$sub_okapi\n" if ($this->{verbose});
# 	    $q2scores[$i]->{dpnd}{$qid} = {tf => $score, tff => $tff, idf => $idf, qtf => $qid2qtf->{$qid}, df => $df, dlength => $dlength, score => $sub_okapi};
# 	}

# 	if ($dpnd_on) {
# 	    $merged_docs[$i]->{score_total} += $okapi_score;
# 	}
# 	$merged_docs[$i]->{score_dpnd} = $okapi_score;

# 	my $score_near = 0;
#  	foreach my $gid (keys %{$gid2near}) {
#  	    next if (defined $did2gid_dpnd{$did}->{$gid});

# 	    $score_near += $gid2near->{$gid};
# 	    $merged_docs[$i]->{score_total} += $gid2near->{$gid} if ($dist_on);
# 	}
# 	$merged_docs[$i]->{score_dist} = $score_near;
# 	$merged_docs[$i]->{q2score} = $q2scores[$i];
#     }

#     @merged_docs = sort {$b->{score_total} <=> $a->{score_total}} @merged_docs;

#     my $finish_time = Time::HiRes::time;
#     my $conduct_time = $finish_time - $start_time;
#     if ($this->{show_speed}) {
# 	printf ("@@@ %.4f sec. doc_list merging.\n", $conduct_time);
#     }

#     return \@merged_docs;
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

	    unless (exists($did2pos_score{$did})) {
		$did2pos_score{$did} = {};
	    }

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

# 	    print $size . "\n";
# 	    print $fnum . "\n";
# 	    print $offset_pos . "\n";
# 	    print $offset_score . "\n";
# 	    print "-----\n";

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
    @{$serialized_docs} = sort {$a->{did} <=> $b->{did}} @{$serialized_docs};

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
