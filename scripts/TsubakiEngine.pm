package TsubakiEngine;

# $Id$

use strict;
use IO::Socket;
use Retrieve;
use Indexer qw(makeIndexfromKnpResult makeIndexfromJumanResult);
use Encode qw(from_to encode decode);
use URI::Escape;
use Storable qw(store retrieve);
use utf8;
use Data::Dumper;
# use Devel::Size qw(total_size);
# use Getopt::Long;
use OKAPI;
use Devel::Size qw/size total_size/;


# host名を得る
my $host = `hostname`; chop($host);

# コンストラクタ
sub new {
    my ($class, $opts) = @_;

    my $start_time = Time::HiRes::time;

    my $this = {
	word_retriever => new Retrieve($opts->{idxdir}, 'word', $opts->{skip_pos}, $opts->{verbose}, $opts->{show_speed}),
	dpnd_retriever => new Retrieve($opts->{idxdir}, 'dpnd', $opts->{skip_pos}, $opts->{verbose}, $opts->{show_speed}),
	DOC_LENGTH_DBs => $opts->{doc_length_dbs},
	AVERAGE_DOC_LENGTH => $opts->{average_doc_length},
	TOTAL_NUMBUER_OF_DOCS => $opts->{total_number_of_docs},
	verbose => $opts->{verbose},
	store_verbose => $opts->{store_verbose},
	dlengthdb_hash => $opts->{dlengthdb_hash},
	WEIGHT_DPND_SCORE => defined $opts->{weight_dpnd_score} ? $opts->{weight_dpnd_score} : 1,
	show_speed => $opts->{show_speed}
    };

    opendir(DIR, $opts->{dlengthdbdir});
    foreach my $dbf (readdir(DIR)) {
 	next unless ($dbf =~ /doc_length\.bin/);

 	my $fp = "$opts->{dlengthdbdir}/$dbf";
 	my $dlength_db;
 	# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
 	if ($opts->{dlengthdb_hash}) {
 	    require CDB_File;
 	    tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
 	}
 	else {
	    $dlength_db = retrieve($fp) or die;
 	}

 	push(@{$this->{DOC_LENGTH_DBs}}, $dlength_db);
    }
    closedir(DIR);

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

sub search {
    my ($this, $query, $qid2df) = @_;

    my $start_time = Time::HiRes::time;

    # 検索
    my ($alldocs_word, $alldocs_dpnd) = $this->retrieve_documents($query);
    
    my $cal_method;
    if ($query->{only_hitcount}) {
	$cal_method = undef; # ヒットカウントのみの場合はスコアは計算しない
    } else {
	$cal_method = new OKAPI($this->{AVERAGE_DOC_LENGTH}, $this->{TOTAL_NUMBUER_OF_DOCS}, $this->{verbose});
    }

    # 文書のスコアリング
    my $doc_list = $this->merge_docs($alldocs_word, $alldocs_dpnd, $qid2df, $cal_method, $query->{qid2qtf});

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. search method calling.\n", $conduct_time);
    }

    return $doc_list;
}

## 単語を含む文書の検索
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

    # todo: クエリが重なったときの対応について考える
    my $ret = $this->serialize2(\@results, \%idx2qid);

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doclist retrieving from dat.\n", $conduct_time);
    }

    return $ret;
}

# 文書のスコアリング
sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $qid2df, $cal_method, $qid2qtf) = @_;

    my $start_time = Time::HiRes::time;

    my $pos = 0;
    my %did2pos = ();
    my @merged_docs = ();
    my %d_length_buff = ();

    # 検索キーワードごとに区切る
    foreach my $docs_word (@{$alldocs_words}) {
	foreach my $doc (@{$docs_word}) {
	    my $i;
	    my $did = $doc->{did};
	    if (exists($did2pos{$did})) {
		$i = $did2pos{$did};
	    } else {
		$i = $pos;
		$merged_docs[$pos] = {did => $did, score => 0};
		$did2pos{$did} = $pos;
		$pos++;
	    }

	    if (defined($cal_method)) {
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

		    my $score = $cal_method->calculate_score({tf => $tf, df => $df, length => $dlength});
		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n" if ($this->{verbose});

		    $merged_docs[$i]->{score} += $score * $qtf;
		    push @{$merged_docs[$i]->{verbose}}, { qid => $qid, tf => $tf, df => $df, length => $dlength, score => $score} if $this->{store_verbose};
		}
	    }
	}
    }

    unless (defined($cal_method)) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	if ($this->{show_speed}) {
	    printf ("@@@ %.4f sec. doclist merging.\n", $conduct_time);
	}
	return \@merged_docs;
    }

    foreach my $docs_dpnd (@{$alldocs_dpnds}) {
	foreach my $doc (@{$docs_dpnd}) {
	    my $did = $doc->{did};
	    if (exists($did2pos{$did})) {
		my $i = $did2pos{$did};
		foreach my $qid_freq (@{$doc->{qid_freq}}) {
		    my $tf = $qid_freq->{freq};
		    my $qid = $qid_freq->{qid};
		    my $df = $qid2df->{$qid};
		    my $qtf = $qid2qtf->{$qid};
		    my $dlength = $d_length_buff{$did};

		    my $score = $cal_method->calculate_score({tf => $tf, df => $df, length => $dlength});
		    $score *= $this->{WEIGHT_DPND_SCORE};

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n" if ($this->{verbose});

		    $merged_docs[$i]->{score} += $score * $qtf;
		    push @{$merged_docs[$i]->{verbose}}, { qid => $qid, tf => $tf, df => $df, length => $dlength, score => $score} if ($this->{store_verbose});
		}
	    }
	}
    }
    
    @merged_docs = sort {$b->{score} <=> $a->{score}} @merged_docs;

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doc_list merging.\n", $conduct_time);
    }

    return \@merged_docs;
}

sub retrieve_documents {
    my ($this, $query) = @_;

    my $start_time = Time::HiRes::time;

    my $alldocs_word = [];
    my $alldocs_dpnd = [];
    my $doc_buff = {};
    my $add_flag = 1;
    foreach my $keyword (@{$query->{keywords}}) {
	my $docs_word = [];
	my $docs_dpnd = [];
	# keyword中の単語を含む文書の検索
	# todo: AND の場合は文書頻度の低い単語から検索する
	foreach my $reps_of_word (@{$keyword->{words}}) {
	    if ($this->{verbose}) {
		foreach my $rep_of_word (@{$reps_of_word}) {
		    foreach my $k (keys %{$rep_of_word}) {
			print $k . " " . encode('euc-jp', $rep_of_word->{$k}) . "\n";
		    }
		}
	    }

	    # バイナリファイルから文書の取得
	    my $docs = $this->retrieve_from_dat($this->{word_retriever}, $reps_of_word, $doc_buff, $add_flag, $keyword->{near}, $keyword->{sentence_flag}, $keyword->{syngraph});
	    print $add_flag . "=aflag\n" if ($this->{verbose}) ;
	    $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR' || $keyword->{near} > -1));

	    print scalar(@$docs) . "=size\n" if ($this->{verbose});

	    # 各語について検索された結果を納めた配列に push
	    push(@{$docs_word}, $docs);
	}

	$add_flag = 1;
	# keyword中の係り受けを含む文書の検索
	foreach my $reps_of_dpnd (@{$keyword->{dpnds}}) {
	    if ($this->{verbose}) {
		foreach my $rep_of_dpnd (@{$reps_of_dpnd}) {
		    foreach my $k (keys %{$rep_of_dpnd}) {
			print $k . " " . encode('euc-jp', $rep_of_dpnd->{$k}) ."\n";
		    }
		}
	    }

	    # バイナリファイルから文書の取得
	    my $docs = $this->retrieve_from_dat($this->{dpnd_retriever}, $reps_of_dpnd, $doc_buff, $add_flag, $keyword->{near}, $keyword->{sentence_flag}, $keyword->{syngraph});
	    print $add_flag . "=aflag\n" if ($this->{verbose});
	    $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR' || $keyword->{near} > -1));

	    print scalar(@$docs) . "=size\n" if ($this->{verbose});

	    # 各係受けについて検索された結果を納めた配列に push
	    push(@{$docs_dpnd}, $docs);
	}
	
	# 検索キーワードごとに検索された文書の配列へpush
	if ($keyword->{logical_cond_qkw} eq 'OR') {
	    # 検索キーワード中の単語間のORをとる 
	    # 文書配列の直列化
	    push(@{$alldocs_word}, &serialize($docs_word));
	    push(@{$alldocs_dpnd}, &serialize($docs_dpnd));
	} else {
	    # 検索キーワード中の単語間のANDをとる
	    $docs_word = &intersect($docs_word);
	    $docs_dpnd = &intersect($docs_dpnd);
	    
	    # 係り受け制約の適用
	    if (scalar(@{$keyword->{dpnds}}) > 0 && $keyword->{force_dpnd} > 0) {
		$docs_word = $this->filter_by_force_dpnd_constraint($docs_word, $docs_dpnd);
	    }
	    
	    # 近接制約の適用
	    $docs_word = $this->filter_by_NEAR_constraint($docs_word, $keyword->{near}, $keyword->{sentence_flag});
	    
	    # 文書配列の直列化
	    push(@{$alldocs_word}, &serialize($docs_word));
	    push(@{$alldocs_dpnd}, &serialize($docs_dpnd));
	}
    }

    # 論理条件にしたがい文書のマージ
    if ($query->{logical_cond_qk} eq 'AND') {
	$alldocs_word =  &intersect($alldocs_word);
    } else {
	# 何もしなければ OR
    }

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
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

# 配列の配列を受け取り OR をとる (配列の配列をマージして単一の配列にする)
sub serialize2 {
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
	    my $poss = $d->[2];
	    if (exists($did2pos{$did})) {
		my $j = $did2pos{$did};
		push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, freq => $freq});
	    } else {
		$serialized_docs->[$pos] = {did => $did, qid_freq => [{qid => $qid, freq => $freq}]};
		$serialized_docs->[$pos]->{pos} = $poss if (defined($poss));
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

# 配列の配列を受け取り、各配列間の共通要素をとる
sub intersect {
    my ($docs) = @_;

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
    }

    return \@results;
}

# 近接条件の適用
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

# 係り受け条件の適用
sub filter_by_force_dpnd_constraint {
    my ($this, $docs_word, $docs_dpnd) = @_;

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
		    for (my $k = 0; $k < scalar(@sorted_docs); $k++) {
			print "loop $i idx $k size " . scalar(@{$sorted_docs[$k]}) ."\n";
			foreach my $ddd (@{$sorted_docs[$k]}) {
			    print $ddd->{did} . " ";
			}
			print "\n";
		    }
		    print "-----\n";
		}

		while (defined($sorted_docs[$j]->[0])) {
		    if ($sorted_docs[$j]->[$idxmap{$j}]->{did} < $sorted_docs[0]->[$i]->{did}) {
			$idxmap{$j}++;
#			shift(@{$sorted_docs[$j]});
		    } elsif ($sorted_docs[$j]->[$idxmap{$j}]->{did} == $sorted_docs[0]->[$i]->{did}) {
			$flag = 0;
			last;
		    } elsif ($sorted_docs[$j]->[$idxmap{$j}]->{did} > $sorted_docs[0]->[$i]->{did}) {
			last;
		    }
		}
		last if ($flag > 0);
	    }

	    $dids{$sorted_docs[0]->[$i]->{did}} = 1 if ($flag < 1);
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
