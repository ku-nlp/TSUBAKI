package TsubakiEngine;

# $Id$

############################################################################
# 検索の流れを管理する（抽象）クラス
# ユーザはこのクラスを継承し以下のメソッドをオーバーライドしなくてはならない
#
# sub merge_docs : 検索条件にマッチした文書をスコアリングするメソッド
# sub merge_search_result : 配列の配列をマージして単一の配列にするメソッド
############################################################################

use strict;
use Retrieve;
use Encode qw(from_to encode decode);
use utf8;
use Devel::Size qw/size total_size/;
use Data::Dumper;
{
    package Data::Dumper;
     sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;


##################################################################
# ★抽象メソッド一覧★
# サブクラスは以下の抽象メソッドをオーバーライドしなくてはならない
##################################################################

# 検索条件にマッチした文書をスコアリングする抽象メソッド
# サブクラスでオーバーライドする必要有
sub merge_docs { die "The method `merge_docs' is not overridden." }

# 配列の配列を受け取り OR をとる抽象メソッド (配列の配列をマージして単一の配列にする)
# サブクラスでオーバーライドする必要有
sub merge_search_result { die "The method `merge_search_result' is not overridden." }



################
# コンストラクタ
################

sub new {
    my ($class, $opts) = @_;

    my $start_time = Time::HiRes::time;
    my $this = {
	word_retriever => undef,
	dpnd_retriever => undef,
	DOC_LENGTH_DBs => $opts->{doc_length_dbs},
	AVERAGE_DOC_LENGTH => $opts->{average_doc_length},
	TOTAL_NUMBUER_OF_DOCS => $opts->{total_number_of_docs},
	verbose => $opts->{verbose},
	store_verbose => $opts->{store_verbose},
	dlengthdb_hash => $opts->{dlengthdb_hash},
	WEIGHT_DPND_SCORE => defined $opts->{weight_dpnd_score} ? $opts->{weight_dpnd_score} : 1,
	show_speed => $opts->{show_speed}
    };

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. TsubakiEngine's constructor calling.\n", $conduct_time);
    }

    bless $this;
}

# デストラクタ
sub DESTROY {
    my ($this) = @_;

    if ($this->{dlengthdb_hash}) {
	foreach my $db (@{$this->{DOC_LENGTH_DBs}}) {
	    untie %{$db};
	}
    }
}

# 検索を行うメソッド
sub search {
    my ($this, $query, $qid2df, $opt) = @_;

    my $start_time = Time::HiRes::time;
    # 検索
    # 文書のスコアリング
    my ($alldocs_word, $alldocs_dpnd) = $this->retrieve_documents($query, $qid2df);

    my $cal_method = 1;
    if ($query->{only_hitcount} > 0) {
	$cal_method = undef; # ヒットカウントのみの場合はスコアは計算しない
    }

    # 文書のスコアリング
    my $doc_list = $this->merge_docs($alldocs_word, $alldocs_dpnd, $qid2df, $cal_method, $query->{qid2qtf}, $query->{dpnd_map}, $query->{qid2gid}, $opt->{flag_of_dpnd_use}, $opt->{flag_of_dist_use}, $opt->{DIST}, $opt->{MIN_DLENGTH}, $query->{gid2weight});

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. search method calling.\n", $conduct_time);
    }

    return $doc_list;
}

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
	$results[$i] = $retriever->search($rep, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag);

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

sub get_minimum_distance {
    my ($this, $poslist1, $poslist2, $dlength) = @_;

    my $MAX = 1000000;
    my $min_dist = $MAX;
    return -1 unless (defined $poslist1 && defined $poslist2);

    my $j = 0;
    for (my $i = 0; $i < scalar(@{$poslist1}); $i++) {
	while ($poslist1->[$i] > $poslist2->[$j] && $j < scalar(@{$poslist2})) {
	    $j++;
	}

	last unless ($j < scalar(@{$poslist2}));

	my $dist = $poslist2->[$j] - $poslist1->[$i];
	$min_dist = $dist if ($min_dist > $dist);
    }

    return $min_dist;
}

sub calculate_score {
    my ($this, $freq, $gdf, $length, $ave_doc_length, $total_number_of_docs) = @_;
    return -1 if ($freq <= 0 || $gdf <= 0 || $length <= 0);

    my $tf = (3 * $freq) / ((0.5 + 1.5 * $length / $ave_doc_length) + $freq);
#    print "log(($this->{total_number_of_docs} - $gdf + 0.5) / ($gdf + 0.5))\n" if ($this->{debug});
    my $idf =  log(($total_number_of_docs - $gdf + 0.5) / ($gdf + 0.5));

    return $tf * $idf;
}

sub retrieve_documents {
    my ($this, $query, $qid2df) = @_;

    my $start_time = Time::HiRes::time;

    my $alldocs_word = [];
    my $alldocs_dpnd = [];
    my $requisite_docs = undef;
    my $doc_buff = {};
    # requisiteである単語を含む文書の検索
    foreach my $keyword (@{$query->{keywords}}) {
	my $docs_word = [];
	my $j = 0;
	my $add_flag = 1;
	my $requisite_flag = 0;

	# 文書頻度の低い単語から検索する
	next unless (defined $keyword->{dpnds});
	foreach my $reps_of_word (sort {$qid2df->{$a->[0]{qid}} <=> $qid2df->{$b->[0]{qid}}} @{$keyword->{dpnds}}) {
	    my %idx2qid = ();
	    my @results = ();
	    for (my $i = 0; $i < scalar(@{$reps_of_word}); $i++) {
		# rep は構造体
		# rep = {qid, string}
		my $rep = $reps_of_word->[$i];
		next unless ($rep->{requisite});

		$requisite_flag = 1;
		# 戻り値は 0番めがdid, 1番めがfreqの配列の配列 [[did1, freq1], [did2, freq2], ...]
		$results[$j] = $this->{dpnd_retriever}->search($rep, $doc_buff, $add_flag, $query->{only_hitcount}, $keyword->{sentence_flag}, $keyword->{syngraph});

		$idx2qid{$j++} = $rep->{qid};
		$add_flag = 0;

		my $docs = $this->merge_search_result(\@results, \%idx2qid);

		# 各語について検索された結果を納めた配列に push
		push(@{$docs_word}, $docs);
	    }
	}

	if ($requisite_flag > 0) {
	    $docs_word = &intersect($docs_word);
	    $requisite_docs = &serialize($docs_word);
	}
    }

    ##########
    # 通常検索
    ##########
    foreach my $keyword (@{$query->{keywords}}) {
	my $docs_word = [];
	my $docs_dpnd = [];

	# keyword中の単語を含む文書の検索
	# 文書頻度の低い単語から検索する
 	my $add_flag = 1;
	foreach my $reps_of_word (sort {$qid2df->{$a->[0]{qid}} <=> $qid2df->{$b->[0]{qid}}} @{$keyword->{words}}) {
	    if ($this->{verbose}) {
		foreach my $rep_of_word (@{$reps_of_word}) {
		    foreach my $k (keys %{$rep_of_word}) {
			my $v = $rep_of_word->{$k};
			$v = decode('utf8', $v) unless (utf8::is_utf8($v));
			print $k . " " . $v . "\n";
		    }
		}
	    }

	    # バイナリファイルから文書の取得
 	    my $docs = $this->retrieve_from_dat($this->{word_retriever}, $reps_of_word, $doc_buff, $add_flag, $query->{only_hitcount}, $keyword->{sentence_flag}, $keyword->{syngraph});

 	    print $add_flag . "=aflag\n" if ($this->{verbose}) ;
 	    $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR' || $keyword->{near} > -1));
 	    print scalar(@$docs) . "=size\n" if ($this->{verbose});

 	    # 各語について検索された結果を納めた配列に push
 	    push(@{$docs_word}, $docs);
	    print "-----\n" if ($this->{verbose});
	}

	$add_flag = 1;
	# keyword中の係り受けを含む文書の検索
	foreach my $reps_of_dpnd (@{$keyword->{dpnds}}) {
	    if ($this->{verbose}) {
		foreach my $rep_of_dpnd (@{$reps_of_dpnd}) {
		    foreach my $k (keys %{$rep_of_dpnd}) {
			print $k . " " . $rep_of_dpnd->{$k} ."\n";
		    }
		}
	    }

	    # バイナリファイルから文書の取得
	    my $docs = $this->retrieve_from_dat($this->{dpnd_retriever}, $reps_of_dpnd, $doc_buff, 1, $keyword->{near}, $keyword->{sentence_flag}, $keyword->{syngraph});

#	    print $add_flag . "=aflag\n" if ($this->{verbose});
#	    $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR' || $keyword->{near} > -1));

	    print scalar(@$docs) . "=size\n" if ($this->{verbose});

	    # 各係受けについて検索された結果を納めた配列に push
	    push(@{$docs_dpnd}, $docs);
	}
	
	# 検索キーワードごとに検索された文書の配列へpush
	if ($keyword->{logical_cond_qkw} eq 'OR') {
	    # 検索語について収集された文書をマージ
	    push(@{$alldocs_word}, &serialize($docs_word));
	    push(@{$alldocs_dpnd}, &serialize($docs_dpnd));
	} else {
	    # 検索キーワード中の単語間のANDをとる
	    $docs_word = &intersect($docs_word);
	    # $docs_dpnd = &intersect($docs_dpnd); # ★★★★★ intersect
	    # ★ 整理する
	    
	    # 係り受け制約の適用
	    if (scalar(@{$keyword->{dpnds}}) > 0 && $keyword->{force_dpnd} > 0) {
		$docs_word = $this->filter_by_force_dpnd_constraint($docs_word, $docs_dpnd);
	    }
	    
	    # 近接制約の適用
	    if ($keyword->{near} > 0) {
		if ($keyword->{syngraph}) {
		    $docs_word = $this->filter_by_NEAR_constraint($docs_word, $keyword->{near}, $keyword->{sentence_flag});
		} else {
		    $docs_word = $this->filter_by_NEAR_constraint($docs_word, $keyword->{near}, $keyword->{sentence_flag});
		}
	    }

	    # 検索キーワードについて収集された文書をマージ
	    push(@{$alldocs_word}, &serialize($docs_word));
	    push(@{$alldocs_dpnd}, &serialize($docs_dpnd));
	}
    }

    if (defined $requisite_docs) {
	my %dids = ();
	foreach my $e (@$requisite_docs) {
	    $dids{$e->{did}} = 1;
	}

	my @new_alldocs_word = ();
	foreach my $docs (@$alldocs_word) {
	    push(@new_alldocs_word, []);
	    foreach my $d (@$docs) {
		next unless (exists $dids{$d->{did}});

		push(@{$new_alldocs_word[-1]}, $d);
	    }
	}

	$alldocs_word =  \@new_alldocs_word;
    }

    # 論理条件にしたがい検索語ごとに収集された文書のマージ
    if ($query->{logical_cond_qk} eq 'AND') {
	$alldocs_word =  &intersect($alldocs_word);
    } else {
	# 何もしなければ OR
    }

    if ($this->{show_speed}) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	printf ("@@@ %.4f sec. doclist retrieving.\n", $conduct_time);
    }

    return ($alldocs_word, $alldocs_dpnd);
}

# 配列の配列を受け取り OR をとる (配列の配列をマージして単一の配列にする)
sub serialize {
    my ($docs_list) = @_;

    my $serialized_docs = [];
    my $pos = 0;
    my %did2pos = ();
    foreach my $docs (@{$docs_list}) {
	foreach my $d (@{$docs}) {
	    next unless (defined($d)); # 本来なら空はないはず

	    if (exists($did2pos{$d->{did}})) {
		my $i = $did2pos{$d->{did}};
		push(@{$serialized_docs->[$i]->{qid_freq}}, @{$d->{qid_freq}});
	    } else {
		$serialized_docs->[$pos] = $d;
		$did2pos{$d->{did}} = $pos;
		$pos++;
	    }
	}
    }
    @{$serialized_docs} = sort {$a->{did} <=> $b->{did}} @{$serialized_docs};

    return $serialized_docs;
}

# 配列の配列を受け取り、各配列間の共通要素をとる
sub intersect {
    my ($docs, $opt) = @_;

    # 初期化 & 空リストのチェック
    my @results = ();
    my $flag = 0;
    for (my $i = 0; $i < scalar(@{$docs}); $i++) {
	$flag = 1 unless (defined($docs->[$i]));
	$flag = 2 if (scalar(@{$docs->[$i]}) < 1);

	$results[$i] = [];
    }
    return \@results if ($flag > 0 || scalar(@{$docs}) < 1);

    my $variation = scalar(@{$docs});
    if ($variation < 2) {
#	return $docs;
	foreach my $doc (@{$docs->[0]}) {
	    push(@{$results[0]}, $doc);
	}
    } else {
	# 入力リストをサイズ順にソート (一番短い配列を先頭にするため)
	my @sorted_docs = sort {scalar(@{$a}) <=> scalar(@{$b})} @{$docs};

	if ($opt->{verbose}) {
	    print "--------\n";
	    print "start with AND filtering.\n";
	    foreach my $ret (@sorted_docs) {
		print "qid=" . $ret->[0]->{qid_freq}[0]{qid} . ": ";
		foreach my $d (@$ret) {
		    print $d->{did} . " ";
		}
		print "\n";
	    }
	}

	# 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
	for (my $i = 0; $i < scalar(@{$sorted_docs[0]}); $i++) {
	    # 対象の文書を含まない配列があった場合 $flagが 1 のままループを終了する
	    my $flag = 0;
	    # 一番短かい配列以外を順に調べる
	    for (my $j = 1; $j < $variation; $j++) {
		$flag = 1; 
		while (defined($sorted_docs[$j]->[0])) {
		    if ($sorted_docs[$j]->[0]->{did} < $sorted_docs[0]->[$i]->{did}) {
			shift(@{$sorted_docs[$j]});
		    } elsif ($sorted_docs[$j]->[0]->{did} == $sorted_docs[0]->[$i]->{did}) {
			$flag = 0;
			last;
		    } elsif ($sorted_docs[$j]->[0]->{did} > $sorted_docs[0]->[$i]->{did}) {
			last;
		    }
		}
		last if ($flag > 0);
	    }

	    if ($flag < 1) {
		push(@{$results[0]}, $sorted_docs[0]->[$i]);
		for (my $j = 1; $j < scalar(@sorted_docs); $j++) {
		    push(@{$results[$j]}, $sorted_docs[$j]->[0]);
		}
	    }
	}
	if ($opt->{verbose}) {
	    print "-----\n";
	    foreach my $ret (@results) {
		print "qid=" . $ret->[0]->{qid_freq}[0]{qid} . ": ";
		foreach my $d (@$ret) {
		    print $d->{did} . " ";
		}
		print "\n";
	    }
	    print "end with AND filtering.\n";
	    print "-----\n";
	}
    }

    return \@results;
}

# 近接条件の適用
sub filter_by_NEAR_constraint_strict {
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
	my $did = $docs->[0][$d]->{did};
	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@{$docs}); $q++) {
	    my $qid_freq_size = scalar(@{$docs->[$q][$d]->{qid_freq}});

	    if ($qid_freq_size < 2) {
		my $fnum = $docs->[$q][$d]->{qid_freq}[0]{fnum};
		my $nums = $docs->[$q][$d]->{qid_freq}[0]{nums};
		my $offset = $docs->[$q][$d]->{qid_freq}[0]{offset};
		unless (defined $offset) {
		    $poslist[$q] = [];
		} else {
		    my $poss = $this->{word_retriever}->load_position($fnum, $offset, $nums);
		    foreach my $p (@$poss) {
			push(@{$poslist[$q]}, $p);
		    }
		}
	    }
	    # 代表表記化により複数個にわかれたものの出現位置 or 出現文IDのマージ
	    else {
		my %buff = ();
		for (my $j = 0; $j < $qid_freq_size; $j++) {
		    my $fnum = $docs->[$q][$d]->{qid_freq}[$j]{fnum};
		    my $nums = $docs->[$q][$d]->{qid_freq}[$j]{nums};
		    my $offset = $docs->[$q][$d]->{qid_freq}[$j]{offset};
		    next unless (defined $offset);

		    my $poss = $this->{word_retriever}->load_position($fnum, $offset, $nums);
		    foreach my $p (@$poss) {
			$buff{$p} = 1;
		    }
		}

		if (scalar(keys %buff) > 0) {
		    foreach my $p (sort {$a <=> $b} keys %buff) {
			push(@{$poslist[$q]}, $p);
		    }
		} else {
		    $poslist[$q] = [];
		}
	    }
	}

	###########################################################
	# Binarizer.pm のバグのため position がないものはスキップ #
	###########################################################
	while (defined $poslist[0] && scalar(@{$poslist[0]}) > 0) {
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

# 近接条件の適用
sub filter_by_NEAR_constraint {
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
	my $did = $docs->[0][$d]->{did};
	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@{$docs}); $q++) {
	    my $qid_freq_size = scalar(@{$docs->[$q][$d]->{qid_freq}});

	    if ($qid_freq_size < 2) {
		my $fnum = $docs->[$q][$d]->{qid_freq}[0]{fnum};
		my $nums = $docs->[$q][$d]->{qid_freq}[0]{nums};
		my $offset = $docs->[$q][$d]->{qid_freq}[0]{offset};
		unless (defined $offset) {
		    $poslist[$q] = [];
		} else {
		    my $poss = $this->{word_retriever}->load_position($fnum, $offset, $nums);
		    foreach my $p (@$poss) {
			push(@{$poslist[$q]}, $p);
		    }
		}
	    }
	    # 代表表記化により複数個にわかれたものの出現位置 or 出現文IDのマージ
	    else {
		my %buff = ();
		for (my $j = 0; $j < $qid_freq_size; $j++) {
		    my $fnum = $docs->[$q][$d]->{qid_freq}[$j]{fnum};
		    my $nums = $docs->[$q][$d]->{qid_freq}[$j]{nums};
		    my $offset = $docs->[$q][$d]->{qid_freq}[$j]{offset};
		    next unless (defined $offset);

		    my $poss = $this->{word_retriever}->load_position($fnum, $offset, $nums);
		    foreach my $p (@$poss) {
			$buff{$p} = 1;
		    }
		}

		if (scalar(keys %buff) > 0) {
		    foreach my $p (sort {$a <=> $b} keys %buff) {
			push(@{$poslist[$q]}, $p);
		    }
		} else {
		    $poslist[$q] = [];
		}
	    }
	}

	my $q_num = scalar(@poslist);
	my @serialized_poslist = ();

	#####################################################
	# クエリ中の単語の語順にフリーな近接制約の適用
	#  1. 各単語の出現位置をマージ
	#  2. 各単語が$near語以内に現れているかどうかチェック
	#####################################################

	# 1. 各単語の出現位置をマージ
	while (1) {
	    my $min_qk = 0;
	    my $flag = -1;
	    for (my $q = 0; $q < $q_num; $q++) {
		next if (!defined scalar(@{$poslist[$q]}) || scalar(@{$poslist[$q]}) < 1);
		if ($flag < 0) {
		    $min_qk = $q;
		    $flag = 1;
		} else {
		    $min_qk = $q if ($poslist[$q][0] < $poslist[$min_qk][0]);
		}
	    }
	    last if ($flag < 0);

	    my $pos = shift(@{$poslist[$min_qk]});
	    push(@serialized_poslist, {pos => $pos, qk => $min_qk});
	}

	#  2. 各単語が$near語以内に現れているかどうかチェック
	my $flag = -1;
	for (my $i = 0; $i < scalar(@serialized_poslist); $i++) {
	    my %qk_buf = ();
	    my $pos = $serialized_poslist[$i]->{pos};
	    for (my $j = $i + 1; $j < scalar(@serialized_poslist); $j++) {
		if ($serialized_poslist[$j]->{pos} - $pos < $near) {
		    $qk_buf{$serialized_poslist[$i]->{qk}}++;
		    $qk_buf{$serialized_poslist[$j]->{qk}}++;
		} else {
		    last;
		}
	    }
	    if (scalar(keys %qk_buf) > $q_num - 1) {
		$flag = 1;
		last;
	    }
	}

	#  $flag > 0 ならば$near語以内にクエリ内の語が出現
	if ($flag > 0) {
	    for (my $q = 0; $q < scalar(@{$docs}); $q++) {
		push(@{$results[$q]}, $docs->[$q][$d]);
	    }
	}
    }

    return \@results;
}

sub filter_by_force_dpnd_constraint {
    my ($this, $docs_word, $docs_dpnd) = @_;

    print "running force_dpnd_filter.\n" if ($this->{verbose});

    # 初期化 & 空リストのチェック
    my @results = ();
    my $flag = 0;
    for (my $i = 0; $i < scalar(@{$docs_word}); $i++) {
	$flag = 1 unless (defined($docs_word->[$i]));
	$flag = 2 if (scalar(@{$docs_word->[$i]}) < 1);

	$results[$i] = [];
    }
    return \@results if ($flag > 0 || scalar(@{$docs_word}) < 1);

    for (my $i = 0; $i < scalar(@{$docs_dpnd}); $i++) {
	$flag = 1 unless (defined($docs_dpnd->[$i]));
	$flag = 2 if (scalar(@{$docs_dpnd->[$i]}) < 1);
    }
    return \@results if ($flag > 0 || scalar(@{$docs_dpnd}) < 1);

    my %dids = ();
    my $variation = scalar(@{$docs_dpnd});
    if ($variation < 2) {
	foreach my $doc (@{$docs_dpnd->[0]}) {
	    $dids{$doc->{did}} = 1;
	}
    } else {
	# 入力リストをサイズ順にソート (一番短い配列を先頭にするため)
	my @sorted_docs = sort {scalar(@{$a}) <=> scalar(@{$b})} @{$docs_dpnd};
	# 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる

	my %idxmap = ();
	for (my $j = 1; $j < $variation; $j++) {
	    $idxmap{$j} = 0;
	}

	for (my $i = 0; $i < scalar(@{$sorted_docs[0]}); $i++) {
	    # 対象の文書を含まない配列があった場合 $flagが 1 のままループを終了する
	    my $flag = 0;
	    # 一番短かい配列以外を順に調べる
	    for (my $j = 1; $j < $variation; $j++) {
		$flag = 1; 
		if ($this->{verbose}) {
		    $idxmap{0} = $i;
		    for (my $k = 0; $k < scalar(@sorted_docs); $k++) {
			print "-----\n";
			print "loop=$i idx=$k size=" . scalar(@{$sorted_docs[$k]}) ."\n";
			for (my $m = $idxmap{$k}; $m < scalar(@{$sorted_docs[$k]}); $m++) {
			    print " " . $sorted_docs[$k][$m]->{did};
			}
			print "\n";
		    }
		}

		while ($idxmap{$j} < scalar(@{$sorted_docs[$j]})) {
		    if ($sorted_docs[$j]->[$idxmap{$j}]->{did} < $sorted_docs[0]->[$i]->{did}) {
			$idxmap{$j}++;
		    } elsif ($sorted_docs[$j]->[$idxmap{$j}]->{did} == $sorted_docs[0]->[$i]->{did}) {
			$flag = 0;
			last;
		    } elsif ($sorted_docs[$j]->[$idxmap{$j}]->{did} > $sorted_docs[0]->[$i]->{did}) {
			last;
		    }
		}
		last if ($flag > 0);
	    }

	    if ($flag < 1) {
		$dids{$sorted_docs[0]->[$i]->{did}} = 1;
		if ($this->{verbose}) {
		    print $sorted_docs[0]->[$i]->{did} . " -> OK.\n";
		    print "-----\n";
		}
	    }
	}
    }

    for (my $i = 0; $i < scalar(@{$docs_word}); $i++) {
	foreach my $doc (@{$docs_word->[$i]}) {
	    next unless (exists($dids{$doc->{did}}));

	    push(@{$results[$i]}, $doc);
	}
    }

    return \@results;
}

1;
