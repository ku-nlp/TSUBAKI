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
use Logger;
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
	idxdir4anchor => $opts->{idxdir4anchor},
	store_verbose => $opts->{store_verbose},
	dlengthdb_hash => $opts->{dlengthdb_hash},
	score_verbose => $opts->{score_verbose},
	logging_query_score => $opts->{logging_query_score},
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

    # 検索
    my ($alldocs_word, $alldocs_dpnd, $alldocs_word_anchor, $alldocs_dpnd_anchor, $did2region) = $this->retrieve_documents($query, $qid2df, $opt->{flag_of_anchor_use}, $opt->{LOGGER});

    my $cal_method = 1;
    if ($query->{only_hitcount} > 0) {
	$cal_method = undef; # ヒットカウントのみの場合はスコアは計算しない (まじめに考える)
    }
#     # ヒットカウントのみならば、文書IDのリストを返して終了
#     if ($query->{only_hitcount} > 0) {
# 	my %buf = ();
# 	foreach my $docs (@$alldocs_word) {
# 	    foreach my $doc (@$docs) {
# 		$buf{$doc->{did}} = 1;
# 	    }
# 	}
# 	my @dids = keys %buf;

# 	return \@dids;
#     }



    my %gid2df;
    foreach my $qkw (@{$query->{keywords}}) {
	foreach my $words (@{$qkw->{words}}) {
	    foreach my $word (@$words) {
		if ($word->{isBasicNode}) {
		    $gid2df{$word->{gid}} = $word->{df};
		}
	    }
	}

	foreach my $dpnds (@{$qkw->{dpnds}}) {
	    foreach my $dpnd (@$dpnds) {
		next unless ($dpnd->{isBasicNode});

		$gid2df{$dpnd->{gid}} = $dpnd->{df};
	    }
	}
    }


    my @dpnds;
    foreach my $qkw (@{$query->{keywords}}) {
	foreach my $ds (@{$qkw->{dpnds}}) {
	    foreach my $dpnd (@$ds) {
		next unless ($dpnd->{isBasicNode});

		my ($moto, $saki) = split("/", $dpnd->{gid});
		push(@dpnds, {gid => $dpnd->{gid}, moto => $moto, saki => $saki});
	    }
	}
    }


    # 文書のスコアリング
    my $doc_list = $this->merge_docs($alldocs_word, $alldocs_dpnd, $alldocs_word_anchor, $alldocs_dpnd_anchor, $query->{qid2qtf}, $query->{qid2gid}, $opt->{flag_of_dpnd_use}, $opt->{flag_of_dist_use}, $opt->{DIST}, \%gid2df, \@dpnds);
    $opt->{LOGGER}->setTimeAs('document_scoring', '%.3f');


    # クエリが出現している範囲をセット
    foreach my $doc (@$doc_list) {
	my $did = $doc->{did};
	if (exists $did2region->{$did}) {
	    $doc->{start} = $did2region->{$did}{start};
	    $doc->{end} = $did2region->{$did}{end};
	    $doc->{pos2qid} = $did2region->{$did}{pos2qid};
	} else {
	    $doc->{start} = -1;
	    $doc->{end} = -1;
	    $doc->{pos2qid} = ();
	}
    }
    $opt->{LOGGER}->setTimeAs('region_setting', '%.3f');

    return $doc_list;
}

# インデックスファイルから単語を含む文書の検索
sub retrieve_from_dat {
    my ($this, $retriever, $reps, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag) = @_;

    my $start_time = Time::HiRes::time;

    ## 代表表記化／SynGraph により複数個の索引に分割された場合の処理 (かんこう -> 観光 OR 刊行 OR 敢行 OR 感光 を検索する)
    my %idx2qid;
    my @results;
    my $logger = new Logger();
    for (my $i = 0; $i < scalar(@{$reps}); $i++) {
	my $rep = $reps->[$i];

	# ------------
	# rep は構造体
	# ------------

	# 'NE' => '<NE:PERSON:宮部みゆき>'
	# 'df' => 1662
	# 'freq' => 1
	# 'fstring' => '<疑似代表表記><代表表記:宮部/みやべ><正規化代表表記:宮部/みやべ><文頭><漢字><かな漢字><名詞相当語><自立><内容語><タグ単位始><文節始><固有キー><NE:PERSON:head>'
	# 'gdf' => 1662
	# 'gid' => 0.0
	# 'isBasicNode' => 1
	# 'isContentWord' => 1
	# 'optional' => 0
	# 'qid' => 0
	# 'question_type' => undef
	# 'requisite' => 1
	# 'string' => '宮部+みゆき'
	# 'stylesheet' => 'background-color: ffffaa; color: black; margin:0.1em 0.25em;'
	# 'surf' => '宮部みゆきの'
	# 'weight' => 1


	# $retriever->search($rep, $doc_buff, $add_flag, $position);
	# 戻り値は 0番めがdid, 1番めがfreqの配列の配列 [[did1, freq1], [did2, freq2], ...]
	$results[$i] = $retriever->search($rep, $doc_buff, $add_flag, $position, $sentence_flag, $syngraph_flag, $logger);
	$logger->setTimeAs(sprintf ("index_access_of_%s", $rep->{string}), '%.3f');

	if ($this->{verbose}) {
	    print "qid " . $rep->{qid} . " ";
	    foreach my $d (@{$results[$i]}) {
		print $d->[0] . " ";
	    }
	    print "\n";
	}

	$idx2qid{$i} = $rep->{qid};
    }
    print "-----\n" if ($this->{verbose});


    my $ret = $this->merge_search_result(\@results, \%idx2qid);
    $logger->setTimeAs(sprintf ("merge_synonyms_and_repnames_of_%s", $reps->[0]{string}), '%.3f');

    if ($this->{show_speed}) {
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	printf ("@@@ %.4f sec. doclist retrieving from dat.\n", $conduct_time);
    }

    return ($ret, $logger);
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


sub retrieveFromBinaryData {
    my ($this,  $query, $qid2df, $keyword, $flag_of_anchor_use, $logger) = @_;

    # 検索にアンカーテキストを考慮する
    if ($flag_of_anchor_use && !$this->{disable_anchor}) {
	$this->{word_retriever4anchor} = new Retrieve($this->{idxdir4anchor}, 'word', 1, $this->{verbose}, $this->{show_speed});
	$this->{dpnd_retriever4anchor} = new Retrieve($this->{idxdir4anchor}, 'dpnd', 1, $this->{verbose}, $this->{show_speed});
    } else {
	if ($flag_of_anchor_use) {
	    print STDERR "エラー: オプションの指定が矛盾しています。 (flag_of_anchor_use -> 1, disable_anchor -> 1)\n";
	    exit 1;
	}
    }

    my $add_flag = 1;
    my $first_requisite_item = 1;
    my ($ret, %requisiteDocBuf);
    my @loggers;
    # 係り受けから検索する
    foreach my $T (('dpnds', 'words')) {

	# keyword中の単語を含む文書の検索
	# 文書頻度の低い単語から検索する
	foreach my $repnames (sort {$qid2df->{$a->[0]{qid}} <=> $qid2df->{$b->[0]{qid}}} @{$keyword->{$T}}) {
	    my $add_flag = 1;
	    my $docbuf = ();
	    if ($keyword->{logical_cond_qkw} =~ /AND/ && $repnames->[0]->{requisite}) {
		# 一番最初の必須要素のみ追加する
		if ($first_requisite_item) {
		    $first_requisite_item = 0;
		} else {
		    $add_flag = 0;
		}
		$docbuf = \%requisiteDocBuf;
	    }


	    # バイナリファイルから文書の取得
	    my $retriever = ($T eq 'dpnds') ? $this->{dpnd_retriever} : $this->{word_retriever};
	    my ($docs, $logger) = $this->retrieve_from_dat($retriever, $repnames, $docbuf, $add_flag, $query->{only_hitcount}, $keyword->{sentence_flag}, $keyword->{syngraph});

	    # 各検索単語・係り受けについて検索された結果を納めた配列に push
	    my $cont = ($repnames->[0]->{requisite}) ? 'requisite' : 'optional';
	    push (@{$ret->{$T}{$cont}}, $docs);



	    # 検索にアンカーテキストを考慮する
	    if ($flag_of_anchor_use) {
		my $add_flag = 1;
		my $dumyDocBuf = ();
		my $anchor_retriever = ($T eq 'dpnds') ? $this->{dpnd_retriever4anchor} : $this->{word_retriever4anchor};
		my ($anchor_docs, $anchor_logger) = $this->retrieve_from_dat($anchor_retriever, $repnames, $dumyDocBuf, $add_flag, $query->{only_hitcount}, $keyword->{sentence_flag}, $keyword->{syngraph});
		foreach my $k ($anchor_logger->keys()) {
		    my $v = $anchor_logger->getParameter($k);
		    $logger->setParameterAs('anchor_' . $k, $v);
		}
		push (@{$ret->{$T}{anchor}}, $anchor_docs);
	    }

	    push (@loggers, $logger);
	}
    }

    return ($ret->{words}{requisite}, $ret->{dpnds}{requisite}, $ret->{words}{optional}, $ret->{dpnds}{optional}, $ret->{words}{anchor}, $ret->{dpnds}{anchor}, \@loggers);

# use Data::Dumper;
# print Dumper($ret->{word}{requisite}) . "\n";
#
# $VAR1 = [
#           [
#             {
#               'did' => 34000954,
#               'qid_freq' => [
#                               {
#                                 'qid' => 0,
#                                 'fnum' => 0,
#                                 'offset_score' => '9038042087',
#                                 'nums' => 113,
#                                 'offset' => '9038037567'
#                               },
#                               {
#                                 'qid' => 1,
#                                 'fnum' => 0,
#                                 'offset_score' => '4374239993',
#                                 'nums' => 115,
#                                 'offset' => '4374235381'
#                               }
#                             ]
#             },
#           :
#           :
#           :
#             {
#               'did' => 34986766,
#               'qid_freq' => [
#                               {
#                                 'qid' => 0,
#                                 'fnum' => 0,
#                                 'offset_score' => '9038044867',
#                                 'nums' => 6,
#                                 'offset' => '9038042059'
#                               },
#                               {
#                                 'qid' => 1,
#                                 'fnum' => 0,
#                                 'offset_score' => '4374242827',
#                                 'nums' => 6,
#                                 'offset' => '4374239965'
#                               }
#                             ]
#             }
#           ],
#           [
#             {
#               'did' => 34000954,
#               'qid_freq' => [
#                               {
#                                 'qid' => 2,
#                                 'fnum' => 0,
#                                 'offset_score' => '8320560358',
#                                 'nums' => 45,
#                                 'offset' => '8319293776'
#                               },
#                               {
#                                 'qid' => 3,
#                                 'fnum' => 0,
#                                 'offset_score' => 463302011,
#                                 'nums' => 45,
#                                 'offset' => 462035429
#                               },
#                               {
#                                 'qid' => 4,
#                                 'fnum' => 0,
#                                 'offset_score' => '1282992072',
#                                 'nums' => 45,
#                                 'offset' => '1281725490'
#                               },
#                               {
#                                 'qid' => 5,
#                                 'fnum' => 0,
#                                 'offset_score' => 460812425,
#                                 'nums' => 45,
#                                 'offset' => 459545843
#                               },
#                               {
#                                 'qid' => 6,
#                                 'fnum' => 0,
#                                 'offset_score' => '6288237291',
#                                 'nums' => 45,
#                                 'offset' => '6286970653'
#                               }
#                             ]
#             },
#           :
#           :
#           :
#             {
#               'did' => 34986766,
#               'qid_freq' => [
#                               {
#                                 'qid' => 2,
#                                 'fnum' => 0,
#                                 'offset_score' => '8321361942',
#                                 'nums' => 3,
#                                 'offset' => '8320545360'
#                               },
#                               {
#                                 'qid' => 3,
#                                 'fnum' => 0,
#                                 'offset_score' => 464103595,
#                                 'nums' => 3,
#                                 'offset' => 463287013
#                               },
#                               {
#                                 'qid' => 4,
#                                 'fnum' => 0,
#                                 'offset_score' => '1283793656',
#                                 'nums' => 3,
#                                 'offset' => '1282977074'
#                               },
#                               {
#                                 'qid' => 5,
#                                 'fnum' => 0,
#                                 'offset_score' => 461614009,
#                                 'nums' => 3,
#                                 'offset' => 460797427
#                               },
#                               {
#                                 'qid' => 6,
#                                 'fnum' => 0,
#                                 'offset_score' => '6289038909',
#                                 'nums' => 3,
#                                 'offset' => '6288222293'
#                               }
#                             ]
#             }
#           ]
#         ];
}


sub get_requisite_docs {
    my ($docs_word, $docs_dpnd) = @_;

    # 必須が指定された検索単語・係り受けを含む文書IDのマージ
    foreach my $ret (@$docs_dpnd) {
	push(@$docs_word, $ret);
    }

    return &intersect($docs_word);
}

sub get_optional_docs {
    my ($docs_word, $docs_dpnd) = @_;

    # 必須が指定された検索単語・係り受けを含む文書IDのマージ
    foreach my $ret (@$docs_dpnd) {
	push(@$docs_word, $ret);
    }

    return $docs_word;
}








sub retrieveFromBinaryData2 {
    my ($this, $retriever, $query, $qid2df, $keyword, $type, $alwaysAppend, $requisite_only, $optional_only) = @_;

    my @loggers = ();
    my @results = ();
    my $add_flag = 1;
    my $docbuf = {};
    # keyword中の単語を含む文書の検索
    # 文書頻度の低い単語から検索する
    foreach my $reps (sort {$qid2df->{$a->[0]{qid}} <=> $qid2df->{$b->[0]{qid}}} @{$keyword->{$type}}) {
	if ($this->{verbose}) {
	    foreach my $rep (@$reps) {
		foreach my $k (keys %$rep) {
		    my $v = $rep->{$k};
		    $v = decode('utf8', $v) unless (utf8::is_utf8($v));
		    print $k . " " . $v . "\n";
		}
	    }
	    print "------\n";
	}
	next if ($reps->[0]{requisite} && $optional_only);
	next if ($reps->[0]{optional} && $requisite_only);


	# バイナリファイルから文書の取得
	my ($docs, $logger) = $this->retrieve_from_dat($retriever, $reps, $docbuf, $add_flag, $query->{only_hitcount}, $keyword->{sentence_flag}, $keyword->{syngraph});
	push (@loggers, $logger);
	unless ($alwaysAppend) {
	    print $add_flag . "=aflag\n" if ($this->{verbose});
	    # $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR' || $keyword->{near} > -1));
	    $add_flag = 0 if ($add_flag > 0 && ($keyword->{logical_cond_qkw} ne 'OR'));
	    print scalar(@$docs) . "=size\n" if ($this->{verbose});
	}

	# 各検索単語・係り受けについて検索された結果を納めた配列に push
	push(@results, $docs);
	print "-----\n" if ($this->{verbose});
    }

# use Data::Dumper;
# print Dumper(\@results) . "\n";
#
# $VAR1 = [
#           [
#             {
#               'did' => 34000954,
#               'qid_freq' => [
#                               {
#                                 'qid' => 0,
#                                 'fnum' => 0,
#                                 'offset_score' => '9038042087',
#                                 'nums' => 113,
#                                 'offset' => '9038037567'
#                               },
#                               {
#                                 'qid' => 1,
#                                 'fnum' => 0,
#                                 'offset_score' => '4374239993',
#                                 'nums' => 115,
#                                 'offset' => '4374235381'
#                               }
#                             ]
#             },
#           :
#           :
#           :
#             {
#               'did' => 34986766,
#               'qid_freq' => [
#                               {
#                                 'qid' => 0,
#                                 'fnum' => 0,
#                                 'offset_score' => '9038044867',
#                                 'nums' => 6,
#                                 'offset' => '9038042059'
#                               },
#                               {
#                                 'qid' => 1,
#                                 'fnum' => 0,
#                                 'offset_score' => '4374242827',
#                                 'nums' => 6,
#                                 'offset' => '4374239965'
#                               }
#                             ]
#             }
#           ],
#           [
#             {
#               'did' => 34000954,
#               'qid_freq' => [
#                               {
#                                 'qid' => 2,
#                                 'fnum' => 0,
#                                 'offset_score' => '8320560358',
#                                 'nums' => 45,
#                                 'offset' => '8319293776'
#                               },
#                               {
#                                 'qid' => 3,
#                                 'fnum' => 0,
#                                 'offset_score' => 463302011,
#                                 'nums' => 45,
#                                 'offset' => 462035429
#                               },
#                               {
#                                 'qid' => 4,
#                                 'fnum' => 0,
#                                 'offset_score' => '1282992072',
#                                 'nums' => 45,
#                                 'offset' => '1281725490'
#                               },
#                               {
#                                 'qid' => 5,
#                                 'fnum' => 0,
#                                 'offset_score' => 460812425,
#                                 'nums' => 45,
#                                 'offset' => 459545843
#                               },
#                               {
#                                 'qid' => 6,
#                                 'fnum' => 0,
#                                 'offset_score' => '6288237291',
#                                 'nums' => 45,
#                                 'offset' => '6286970653'
#                               }
#                             ]
#             },
#           :
#           :
#           :
#             {
#               'did' => 34986766,
#               'qid_freq' => [
#                               {
#                                 'qid' => 2,
#                                 'fnum' => 0,
#                                 'offset_score' => '8321361942',
#                                 'nums' => 3,
#                                 'offset' => '8320545360'
#                               },
#                               {
#                                 'qid' => 3,
#                                 'fnum' => 0,
#                                 'offset_score' => 464103595,
#                                 'nums' => 3,
#                                 'offset' => 463287013
#                               },
#                               {
#                                 'qid' => 4,
#                                 'fnum' => 0,
#                                 'offset_score' => '1283793656',
#                                 'nums' => 3,
#                                 'offset' => '1282977074'
#                               },
#                               {
#                                 'qid' => 5,
#                                 'fnum' => 0,
#                                 'offset_score' => 461614009,
#                                 'nums' => 3,
#                                 'offset' => 460797427
#                               },
#                               {
#                                 'qid' => 6,
#                                 'fnum' => 0,
#                                 'offset_score' => '6289038909',
#                                 'nums' => 3,
#                                 'offset' => '6288222293'
#                               }
#                             ]
#             }
#           ]
#         ];

    return (\@results, \@loggers);
}












sub retrieve_documents {
    my ($this, $query, $qid2df, $flag_of_anchor_use, $logger) = @_;

    my $start_time = Time::HiRes::time;

    my $alldocs_word = [];
    my $alldocs_dpnd = [];
    my $alldocs_word_anchor = [];
    my $alldocs_dpnd_anchor = [];
    my $did2region = ();
    my $doc_buff = {};

    $logger->clearTimer();

    ##########
    # 通常検索
    ##########
    foreach my $keyword (@{$query->{keywords}}) {

	# 検索単語・係り受けの検索

	my ($requisite_docs_word, $requisite_docs_dpnd, $optional_docs_word, $optional_docs_dpnd, $docs_word_anchor, $docs_dpnd_anchor, $sub_loggers) = $this->retrieveFromBinaryData($query, $qid2df, $keyword, $flag_of_anchor_use, $logger);
	$logger->setTimeAs('normal_search', '%.3f');

	# ログを保存
	my $total;
	my $merge_synonyms_total;
	foreach my $sub_logger (@$sub_loggers) {
	    foreach my $k ($sub_logger->keys()) {
		my $v = $sub_logger->getParameter($k);
		$logger->setParameterAs($k, $v);
		$total += $v if ($k =~ /index_access_of/);
		$merge_synonyms_total += $v if ($k =~ /merge_synonyms_and_repnames_of/);
	    }
	}
	$logger->setParameterAs('index_access', sprintf ("%.3f", $total));
	$logger->setParameterAs('merge_synonyms', sprintf ("%.3f", $merge_synonyms_total));


	# 近接制約の適用
	if ($keyword->{near} > 0) {
	    $requisite_docs_word = &intersect($requisite_docs_word, {verbose => $this->{verbose}});
	    ($requisite_docs_word, $did2region) = $this->filter_by_NEAR_constraint($requisite_docs_word, $keyword->{near}, $keyword->{sentence_flag}, $keyword->{keep_order});
	}
	$logger->setTimeAs('near_condition', '%.3f');



	# 必須が指定された検索単語・係り受けを含む文書IDのマージ
	my $requisites = ($keyword->{logical_cond_qkw} =~ /AND/) ? &get_requisite_docs($requisite_docs_word, $requisite_docs_dpnd) : [];
	# オプショナルが指定された検索単語・係り受けを含む文書IDのマージ
	my $optionals = &get_optional_docs($optional_docs_word, $optional_docs_dpnd);



	my %dpnd_qids = ();
	foreach my $reps_of_word (@{$keyword->{dpnds}}) {
	    foreach my $rep (@$reps_of_word) {
		$dpnd_qids{$rep->{qid}} = 1;
	    }
	}

	# requisites, optionals を単語と係り受けに分類する
	my $word_docs = ();
	my $dpnd_docs = ();
	foreach my $docs (@$requisites) {
	    if (defined $docs->[0] && exists $dpnd_qids{$docs->[0]{qid_freq}[0]{qid}}) {
		push(@$dpnd_docs, $docs);
	    } else {
		push(@$word_docs, $docs);
	    }
	}


	if ($keyword->{logical_cond_qkw} =~ /AND/) {
	    # 必須のついた文書IDを取得
	    my %req_ids = ();
	    if (defined $requisites->[0]) {
		foreach my $d (@{$requisites->[0]}) {
		    $req_ids{$d->{did}} = 1;
		}
	    }

	    foreach my $docs (@$optionals) {
		next unless (defined $docs->[0]);

		my @dbuf = ();
		foreach my $d (@$docs) {
		    push(@dbuf, $d) if (exists $req_ids{$d->{did}});
		}

		if (exists $dpnd_qids{$docs->[0]{qid_freq}[0]{qid}}) {
		    push (@$dpnd_docs, \@dbuf);
		} else {
		    push (@$word_docs, \@dbuf);
		}
	    }
	} else {
	    foreach my $docs (@$optionals) {
		next unless (defined $docs->[0]);

		if (exists $dpnd_qids{$docs->[0]{qid_freq}[0]{qid}}) {
		    push(@$dpnd_docs, $docs);
		} else {
		    push(@$word_docs, $docs);
		}
	    }
	}


	# 検索単語・係り受けについて収集された文書をマージ
	push(@{$alldocs_word}, &serialize($word_docs));
	push(@{$alldocs_dpnd}, &serialize($dpnd_docs));

	push(@{$alldocs_word_anchor}, &serialize($docs_word_anchor));
	push(@{$alldocs_dpnd_anchor}, &serialize($docs_dpnd_anchor));
	$logger->setTimeAs('merge_dids', '%.3f');
    }


    # 論理条件にしたがい検索表現ごとに収集された文書のマージ
    if ($query->{logical_cond_qk} eq 'AND') {
	$alldocs_word =  &intersect($alldocs_word);
    } else {
	# 何もしなければ OR
    }
    $logger->setTimeAs('logical_condition', '%.3f');


    return ($alldocs_word, $alldocs_dpnd, $alldocs_word_anchor, $alldocs_dpnd_anchor, $did2region);
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

    next unless defined $docs;

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
	    # SYNGRAPH/代表表記化により複数個にわかれたものの出現位置 or 出現文IDのマージ
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
			# print "$pos < $poslist[$q]->[0] && $poslist[$q]->[0] < ", ($pos + $near - $distance_history) . "\n";
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
    my ($this, $docs, $near, $sentence_flag, $keep_order) = @_;

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

    my %did2region = ();
    for (my $d = 0; $d < scalar(@{$docs->[0]}); $d++) {
	my $did = $docs->[0][$d]->{did};

	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@{$docs}); $q++) {

	    if ($this->{debug}) {
		print STDERR "* did=" . $did . " q=$q d=$d\n";
		require Data::Dumper;
		print STDERR Dumper($docs->[$q][$d]) . "\n";
	    }

	    # 文書$dに含まれている検索語$qの同義表現（または曖昧性のある代表表記）の数
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
	    # 代表表記化またSYNGRAPH化により複数個にわかれた表現・同義グループの出現位置(or 出現文ID)のマージ
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
	# (クエリ中の単語の語順にフリーな)近接制約の適用
	#  1. 各単語の出現位置をマージ
	#  2. 各単語が$near語以内に現れているかどうかチェック
	#####################################################

	# 1. 各単語の出現位置をマージ
	while (1) {
	    my $min_qid = 0;
	    my $flag = -1;
	    for (my $q = 0; $q < $q_num; $q++) {
		next if (!defined scalar(@{$poslist[$q]}) || scalar(@{$poslist[$q]}) < 1);
		if ($flag < 0) {
		    $min_qid = $q;
		    $flag = 1;
		} else {
		    $min_qid = $q if ($poslist[$q][0] < $poslist[$min_qid][0]);
		}
	    }
	    last if ($flag < 0);

	    my $pos = shift(@{$poslist[$min_qid]});
	    push(@serialized_poslist, {pos => $pos, qid => $min_qid});
	}

	if ($this->{debug}) {
	    print "poslist of a document with did=" . $did . ": ";
	    foreach my $p (@serialized_poslist) {
		print $p->{qid} . "/" . $q_num . "@" . $p->{pos} . " ";
	    }
	    print "\n";
	    print "-----\n";
	}


	#  2. 各単語が$near語以内に現れているかどうかチェック
	my $flag = -1;
	for (my $i = 0; $i < scalar(@serialized_poslist); $i++) {
	    my %qid_buf = ();
	    my $pos = $serialized_poslist[$i]->{pos};
	    my $qid = $serialized_poslist[$i]->{qid};

	    # 語順を考慮する場合は、常にqid=0からチェックしなければならない
	    next if ($qid != 0 && $keep_order);

	    my $prev_qid = $qid;
	    push (@{$qid_buf{$serialized_poslist[$i]->{qid}}}, $pos);
	    for (my $j = $i + 1; $j < scalar(@serialized_poslist); $j++) {
		if ($serialized_poslist[$j]->{pos} - $pos < $near) {

		    # 語順を考慮する場合は、隣接しているかどうかチェック
		    if ($keep_order) {
			# 隣あう索引語かどうかのチェック 同じqidの時の対処
			if ($serialized_poslist[$j]->{qid} - $prev_qid != 1) {
			    last;
			} else {
			    # print $serialized_poslist[$j]->{qid} . " - " . $prev_qid . "\n";
			    $prev_qid = $serialized_poslist[$j]->{qid};
			}
		    }
		    push (@{$qid_buf{$serialized_poslist[$i]->{qid}}}, $pos); # 実は要らないかも知れない
		    push (@{$qid_buf{$serialized_poslist[$j]->{qid}}}, $serialized_poslist[$j]->{pos});
		} else {
		    # 指定された近接の範囲を超えた
		    last;
		}
	    }
	    if (scalar(keys %qid_buf) > $q_num - 1) {
		$flag = 1;
		my %posbuf = ();
		foreach my $qid (keys %qid_buf) {
		    foreach my $p (@{$qid_buf{$qid}}) {
			$posbuf{$p} = $qid;
		    }
		}

		my @sorted_pos = sort {$a <=> $b} keys %posbuf;
		$did2region{$did}->{start} = $sorted_pos[0];
		$did2region{$did}->{end} = $sorted_pos[-1];
		$did2region{$did}->{pos2qid} = \%posbuf;
		last;
	    }
	}

	# $flag > 0 ならば$near語以内にクエリ内の語が出現
	if ($flag > 0) {
	    for (my $q = 0; $q < scalar(@{$docs}); $q++) {
		push(@{$results[$q]}, $docs->[$q][$d]);
	    }
	}
    }

    return (\@results, \%did2region);
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
