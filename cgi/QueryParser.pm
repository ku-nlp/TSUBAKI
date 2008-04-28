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


# コンストラクタ
sub new {
    my ($class, $opts) = @_;

    print STDERR "constructing QueryParser object... " if ($opts->{verbose});

    my $CONFIG = Configure::get_instance();
    # パラメータが指定されていなければデフォルト値としてCONFIGから値を取得
    $opts->{KNP_COMMAND} = $CONFIG->{KNP_COMMAND} unless ($opts->{KNP_COMMAND});
    $opts->{JUMAN_COMMAND} = $CONFIG->{JUMAN_COMMAND} unless ($opts->{JUMAN_COMMAND});
    $opts->{KNP_RCFILE} = $CONFIG->{KNP_RCFILE} unless ($opts->{KNP_RCFILE});
    $opts->{KNP_OPTIONS} = $CONFIG->{KNP_OPTIONS} unless ($opts->{KNP_OPTIONS});
    # $opts->{DFDB_DIR} = $CONFIG->{ORDINARY_DFDB_PATH} unless ($opts->{DFDB_DIR});

    my $this = {
	KNP => new KNP(-Command => $opts->{KNP_COMMAND},
		       -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
		       -Rcfile => $opts->{KNP_RCFILE},
		       -JumanCommand => $opts->{JUMAN_COMMAND}),
	OPTIONS => {trimming => $opts->{QUERY_TRIMMING},
		    jyushi => (),
		    keishi => (),
		    syngraph => undef}
    };

    $this->{OPTIONS}{jyushi} = $opts->{JYUSHI} if ($opts->{JYUSHI});
    $this->{OPTIONS}{keishi} = $opts->{KEISHI} if ($opts->{KEISHI});

    my ($dfdbs_w, $dfdbs_d) = &load_DFDBs($opts->{DFDB_DIR});
    $this->{DFDBS_WORD} = $dfdbs_w;
    $this->{DFDBS_DPND} = $dfdbs_d;

    # ストップワードの処理
    unless ($opts->{STOP_WORDS}) {
	$this->{INDEXER} = new Indexer();
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
	$this->{INDEXER} = new Indexer({ STOP_WORDS => \%stop_words });
    }

    print STDERR "done.\n" if ($opts->{verbose});
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
	my $CONFIG = Configure::get_instance();
	push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});
	require SynGraph;

	$this->{SYNGRAPH} = new SynGraph($CONFIG->{SYNDB_PATH});
	$this->{SYNGRAPH_OPTION} = {relation => 1, antonym => 1, hypocut_attachnode => 9};
    }

    ## 空白で区切る
    # $qks_str =~ s/ /　/g;
    foreach my $q_str (split(/(?: )+/, $qks_str)) {
	my $near = $opt->{near};
	my $logical_cond_qkw = 'AND'; # 検索語に含まれる単語間の論理条件
	my $keep_order = 1;
	my $force_dpnd = -1;
	my $sentence_flag = -1;
	my $phrasal_flag = -1;
	# フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/){
	    $phrasal_flag = 1;
	    $q_str = $1;
	    $near = 1;

	    # 同義表現を考慮したフレーズ検索はできない
	    if ($opt->{syngraph} > 0) {
		print "<center>同義表現を考慮したフレーズ検索は実行できません。</center></DIV>\n";
		print "<DIV class=\"footer\">&copy;2007 黒橋研究室</DIV>\n";
		print "</body>\n";
		print "</html>\n";
		exit;
	    }
	}

	# 近接検索かどうかの判定
	if ($q_str =~ /^(.+)?~(.+)$/){
	    # 同義表現を考慮した場合は近接制約を指定できない
	    if ($opt->{syngraph} > 0) {
		print "<center>同義表現を考慮した近接検索は実行できません。</center></DIV>\n";
		print "<DIV class=\"footer\">&copy;2007 黒橋研究室</DIV>\n";
		print "</body>\n";
		print "</html>\n";
		exit;
	    }

	    $q_str = $1;
	    # 検索制約の取得
	    my $constraint_tag = $2;
	    if ($constraint_tag =~ /^(\d+)(W|S)$/i) {
		# 近接制約
		$logical_cond_qkw = 'AND';
		$near = $1;
		$sentence_flag = 1 if ($2 =~ /S/i);
		$keep_order = 0 if ($2 eq 's' || $2 eq 'w');
	    } elsif ($constraint_tag =~ /(AND|OR)/) {
		# 論理条件制約
		$logical_cond_qkw = $1;
	    } elsif ($constraint_tag =~ /FD/) {
		# 係り受け強制制約
		$logical_cond_qkw = 'AND';
		$force_dpnd = 1;
	    }
	}

	## 半角アスキー文字列を全角に置換する
	$q_str = Unicode::Japanese->new($q_str)->h2z->getu;

	my $q;
	if ($opt->{syngraph} > 0) {
	    $q = new QueryKeyword($q_str, $sentence_flag, $phrasal_flag, $near, $keep_order, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}, syngraph => $this->{SYNGRAPH}, syngraph_option => $this->{SYNGRAPH_OPTION}, trimming => $opt->{trimming}, verbose => $opt->{verbose}});
	} else {
	    $q = new QueryKeyword($q_str, $sentence_flag, $phrasal_flag, $near, $keep_order, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}, trimming => $opt->{trimming}, verbose => $opt->{verbose}});
	}

	push(@qks, $q);
    }

    my $qid = 0;
    my %qid2rep = ();
    my %rep2qid = ();
    my %qid2gid = ();
    my %gid2qids = ();
    my %qid2df = ();
    my %dpnd_map = ();
    my %gid2df = ();
    my %qid2qtf = ();
    # 検索語中の各索引語にIDをふる
    foreach my $qk (@qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		$rep2qid{$rep->{string}} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid2gid{$qid} = $rep->{gid};
		push(@{$gid2qids{$rep->{gid}}}, $qid);
		$qid2df{$qid} = $this->get_DF($rep->{string});
		$qid2qtf{$qid} = $rep->{freq};

		$rep->{qid} = $qid;
		$rep->{df} = $qid2df{$qid};

		if ($rep->{isBasicNode}) {
		    $gid2df{$rep->{gid}} = $rep->{df};
		}
		$qid++;
		print $rep->{string} . " " . $rep->{qid} . " " . $rep->{gid} . " " . $rep->{df} . "\n" if ($opt->{verbose});
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		$qid2rep{$qid} = $rep->{string};
		$qid2gid{$qid} = $rep->{gid};
		$qid2df{$qid} = $this->get_DF($rep->{string});
		$qid2qtf{$qid} = $rep->{freq};

		$rep->{qid} = $qid;
		$rep->{df} = $qid2df{$qid};

		push(@{$gid2qids{$rep->{gid}}}, $qid);

		my ($kakarimoto, $kakarisaki) = split('->', $rep->{string});
		my $kakarimoto_qid = $rep2qid{$kakarimoto};
		my $kakarisaki_qid = $rep2qid{$kakarisaki};
		$rep->{kakarimoto_qid} = $kakarimoto_qid;
		$rep->{kakarisaki_qid} = $kakarisaki_qid;
		push(@{$dpnd_map{$rep2qid{$kakarimoto}}}, {kakarisaki_qid => $kakarisaki_qid, dpnd_qid => $qid});

		if ($rep->{isBasicNode}) {
		    $gid2df{$rep->{gid}} = $rep->{df};
		}
		$qid++;
	    }
	}
    }

    # SynNodeのgdfは基本ノードのgdfにする
    if ($opt->{syngraph}) {
	foreach my $qid (keys %qid2gid) {
	    my $gid = $qid2gid{$qid};
	    my $df_of_basic_node = $gid2df{$gid};
	    $df_of_basic_node = 0 unless (defined $df_of_basic_node);
	    $qid2df{$qid} = $df_of_basic_node;
	    print "qid=$qid gid=$gid df=$df_of_basic_node\n" if ($opt->{verbose});
	}
    }

    # 検索クエリを表す構造体
    my $ret = {
	keywords => \@qks,
	logical_cond_qk => $opt->{logical_cond_qk},
	only_hitcount => $opt->{only_hitcount},
	qid2rep => \%qid2rep,
	qid2qtf => \%qid2qtf,
	qid2gid => \%qid2gid,
	qid2df => \%qid2df,
	gid2qids => \%gid2qids,
	dpnd_map => \%dpnd_map
    };



    ###########################################
    # 以下はクエリ処理（削除、重み付け）
    ###########################################

    my %gid2weight = ();
    unless ($this->{OPTIONS}{trimming}) {
	foreach my $qk (@qks) {
	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@{$reps}) {
		    my $gid = $rep->{gid};
		    $gid2weight{$gid} = 1;
		}
	    }
	}
    } else {
	$this->set_head_flag(\@qks);
	$this->set_discarded_flag(\@qks);
 	$this->set_requisite_flag_for_dpnds_in_NE(\@qks);
  	$this->change_weight_keishi(\@qks, $this->{OPTIONS}{keishi});
  	$this->change_weight_jyushi(\@qks, $this->{OPTIONS}{jyushi});
#	$ret = $this->create_new_query_from_NE(\@qks);

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
    my ($dbdir) = @_;

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

    return (\@DF_WORD_DBs, \@DF_DPND_DBs);
}

sub get_DF {
    my ($this, $k) = @_;
    my $k_utf8 = encode('utf8', $k);
    my $gdf = 0;
    my $DFDBs = (index($k, '->') > 0) ? $this->{DFDBS_DPND} : $this->{DFDBS_WORD};
    foreach my $dfdb (@{$DFDBs}) {
	my $val = $dfdb->{$k_utf8};
	if (defined $val) {
	    $gdf += $val;
# 	    last;
 	}
    }
    return $gdf;
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
    my ($this, $query) = @_;

    foreach my $qk (@{$query->{keywords}}) {
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
sub DESTROY {}

1;
