package TsubakiEngine4SynGraphSearch;

# $Id$

# SynGraph 検索を行うクラス

use strict;
use Retrieve;
use Storable qw(store retrieve);
use utf8;

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
sub retrieve_from_dat {
    my ($this, $retriever, $reps, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag) = @_;

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
	$results[$i] = $retriever->search4syngraph($rep, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag);

	$idx2qid{$i} = $rep->{qid};
    }

    my $ret = $this->merge_search_result(\@results, \%idx2qid);

    if ($this->{show_speed}) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	printf ("@@@ %.4f sec. doclist retrieving from dat.\n", $conduct_time);
    }

    return $ret;
}

# 文書のスコアリング
sub merge_docs {
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

		print "$qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums}\n";

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

 		    my $dist = &get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
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

		    my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
		    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));

		    my $pos = $this->{dpnd_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{size});

		    my $size = scalar(@$pos);
		    my $scr = $qtf * $tff * $idf / $size;
		    $scr *= $this->{WEIGHT_DPND_SCORE};

		    $did2gid_dpnd{$did}->{$qid2gid->{$qid}} = 1;

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
sub filter_by_NEAR_constraint {
    my ($docs, $near, $sentence_flag) = @_;

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
