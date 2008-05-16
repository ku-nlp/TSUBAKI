package TsubakiEngine4OrdinarySearch;

# $Id$

# 通常の検索を行うクラス

use strict;
use Retrieve;
use utf8;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}

# TsubakiEngine を継承する
use TsubakiEngine;
@TsubakiEngine4OrdinarySearch::ISA = qw(TsubakiEngine);


sub new {
    my ($class, $opts) = @_;
    my $obj = $class->SUPER::new($opts);

    # DAT ファイルから単語を含む文書を検索する retriever オブジェクトをセットする
    $obj->{word_retriever} = new Retrieve($opts->{idxdir}, 'word', $opts->{skip_pos}, $opts->{verbose}, $opts->{show_speed});

    # DAT ファイルから係り受けを含む文書を検索する retriever オブジェクトをセットする
    $obj->{dpnd_retriever} = new Retrieve($opts->{idxdir}, 'dpnd', 1, $opts->{verbose}, $opts->{show_speed});

    bless $obj;
}

sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $alldocs_words_anchor, $alldocs_dpnds_anchor, $qid2df, $cal_method, $qid2qtf, $dpnd_map, $qid2gid, $dpnd_on, $dist_on, $DIST, $MIN_DLENGTH, $gid2weight) = @_;

    my $start_time = Time::HiRes::time;

    my $pos = 0;
    my %did2pos = ();
    my @merged_docs = ();
    my %d_length_buff = ();
    my @q2scores = ();
    # 検索キーワードごとに区切る
    foreach my $docs_word (@{$alldocs_words}) {
	foreach my $doc (@{$docs_word}) {
	    my $i;
	    my $did = $doc->{did};

	    if (exists($did2pos{$did})) {
		$i = $did2pos{$did};
	    } else {
		$i = $pos;
		$merged_docs[$pos] = {did => $did, word_score => 0, dpnd_score => {}, near_score => {}};
		$did2pos{$did} = $pos;
		$pos++;
	    }

	    my %qid2poslist = ();
	    if ($cal_method) {
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
		    next if ($dlength < $MIN_DLENGTH);

		    my $weight = $gid2weight->{$qid2gid->{$qid}};
		    # 関数化するよりも高速
		    my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
		    # my $tff = (2 * $tf) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf); # k1 = 1, b = 0.6, k3 = 0
		    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
		    my $score = $tff * $idf;
		    $qid2poslist{$qid} = $this->{word_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});

		    print "* did=$did qid=$qid tf=$tf df=$df qtf=$qtf tff=$tff length=$dlength score=$score\n" if ($this->{verbose});

		    $merged_docs[$i]->{word_score} += $score * $qtf * $weight;
		    $q2scores[$i]->{word}{$qid} = {tf => $tf, qtf => $qtf, df => $df, dlength => $dlength, score => $score * $qtf * $weight, weight => $weight};
		    push @{$merged_docs[$i]->{verbose}}, { qid => $qid, tf => $tf, df => $df, length => $dlength, score => $score} if $this->{store_verbose};
		}

		foreach my $qid (keys %$dpnd_map) {
		    foreach my $e (@{$dpnd_map->{$qid}}) {
			my $dpnd_qid = $e->{dpnd_qid};
			my $kakarisaki_qid = $e->{kakarisaki_qid};
			my $dlength = $d_length_buff{$did};

			my $dist = $this->get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
			if ($dist > $DIST || $dist < 0) {
			    $merged_docs[$i]->{near_score}{$dpnd_qid} = 0;
			} else {
			    my $tf = ($DIST - $dist) / $DIST;
			    my $df = $qid2df->{$dpnd_qid};
			    my $qtf = $qid2qtf->{$dpnd_qid};

			    my $score;
			    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
			    if ($df == -1) {
				$score = 0;
			    }
			    else {
				my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
				# my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
				my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
				# $score = $qtf;
				$score = $qtf * $tff * $idf;
				print "* qid=$dpnd_qid dist=$dist rate=$tf df=$df qtf=$qtf score=$score\n"  if ($this->{verbose});
			    }

			    $q2scores[$i]->{near}{$qid} = {dist => $dist, qtf => $qtf, df => $df, dlength => $dlength, score => $score, kakarisaki_qid => $kakarisaki_qid, DIST => $DIST};
			    $merged_docs[$i]->{near_score}{$dpnd_qid} = $score;
			}
		    }
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

		    my $score;
		    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
		    if ($df == -1) {
			$score = 0;
		    }
		    else {
			my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
			# my $tff = (2 * $tf) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf); # k1 = 1, b = 0.6, k3 = 0
			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
			$score = $tff * $idf;
			$score *= $this->{WEIGHT_DPND_SCORE};
		    }

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n" if ($this->{verbose});
		    $q2scores[$i]->{dpnd}{$qid} = {tf => $tf, qtf => $qtf, df => $df, dlength => $dlength, score => $score * $qtf};

		    $merged_docs[$i]->{dpnd_score}{$qid} = $score * $qtf;
		    push @{$merged_docs[$i]->{verbose}}, { qid => $qid, tf => $tf, df => $df, length => $dlength, score => $score} if ($this->{store_verbose});
		}
	    }
	}
    }

    foreach my $docs_word (@{$alldocs_words_anchor}) {
	foreach my $doc (@{$docs_word}) {
	    my $did = $doc->{did};
	    # $this->{verbose} = 1 if ($did =~ /78922624/);
	    $this->{verbose} = 1 if ($did =~ /29939252/);

	    if (exists($did2pos{$did})) {
		my $i = $did2pos{$did};
		foreach my $qid_freq (@{$doc->{qid_freq}}) {
		    my $tf = $qid_freq->{freq};
		    my $qid = $qid_freq->{qid};
		    my $df = $qid2df->{$qid};
		    my $qtf = $qid2qtf->{$qid};
		    my $dlength = $d_length_buff{$did};

		    my $score;
		    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
		    if ($df == -1) {
			$score = 0;
		    }
		    else {
			my $tff = (2 * $tf) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf); # k1 = 1, b = 0.6, k3 = 0
			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
			$score = $tff * $idf;
		    }

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n"; # if ($this->{verbose});
		    $q2scores[$i]->{word_anchor}{$qid} = {tf => $tf, qtf => $qtf, df => $df, dlength => $dlength, score => $score * $qtf};
		    $merged_docs[$i]->{word_anchor}{$qid} = $score * $qtf;
		}
	    }
	    $this->{verbose} = 0;
	}
    }

    foreach my $docs_dpnd (@{$alldocs_dpnds_anchor}) {
	foreach my $doc (@{$docs_dpnd}) {
	    my $did = $doc->{did};

	    $this->{verbose} = 1 if ($did =~ /29939252/);
	    if (exists($did2pos{$did})) {
		my $i = $did2pos{$did};
		foreach my $qid_freq (@{$doc->{qid_freq}}) {
		    my $tf = $qid_freq->{freq};
		    my $qid = $qid_freq->{qid};
		    my $df = $qid2df->{$qid};
		    my $qtf = $qid2qtf->{$qid};
		    my $dlength = $d_length_buff{$did};

		    my $score;
		    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
		    if ($df == -1) {
			$score = 0;
		    }
		    else {
			my $tff = (2 * $tf) / ((0.4 + 0.6 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf); # k1 = 1, b = 0.6, k3 = 0
			my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
			$score = $tff * $idf;
		    }

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n" if ($this->{verbose});
		    $q2scores[$i]->{dpnd_anchor}{$qid} = {tf => $tf, qtf => $qtf, df => $df, dlength => $dlength, score => $score * $qtf};
		    $merged_docs[$i]->{dpnd_anchor}{$qid} = $score * $qtf;
		}
	    }
	    $this->{verbose} = 0;
	}
    }

    my @result;
    for (my $i = 0; $i < @merged_docs; $i++) {
	my $e = $merged_docs[$i];
	my $word_anchor_score;
	while (my ($qid, $score) = each (%{$e->{word_anchor}})) {
	    $word_anchor_score += $score;
	}

	my $dpnd_anchor_score;
	while (my ($qid, $score) = each (%{$e->{dpnd_anchor}})) {
	    $dpnd_anchor_score += $score;
	}

	my $score = $e->{word_score} + $word_anchor_score + $dpnd_anchor_score;
	my $dpnd_score = 0;
	my $dist_score = 0;
	while (my ($qid, $score_of_qid) = each(%{$e->{near_score}})) {
	    if ($e->{dpnd_score}{$qid} == 0) {
		if ($dist_on) {
		    $score += $score_of_qid;
		    $dist_score += $score_of_qid;
		}
	    } else {
		if ($dpnd_on) {
		    $score += $e->{dpnd_score}{$qid};
		    $dpnd_score += $e->{dpnd_score}{$qid};
		}
	    }

	    printf ("did=%09d qid=%02d w=%.3f d=%.3f n=%.3f anchor_w=%.3f anchor_d=%.3f total=%.3f\n", $e->{did}, $qid, $e->{word_score}, $e->{dpnd_score}{$qid}, $score_of_qid, $word_anchor_score, $dpnd_anchor_score, $score) if ($this->{verbose});
	}
	print "-----\n" if ($this->{verbose});

	if ($e->{did} =~ /25526608/) {
	    print "$e->{did} $score $e->{word_score} $dpnd_score $dist_score\n";
	}

	push(@result, {did => $e->{did},
		       score_total => $score,
		       score_word => $e->{word_score},
		       score_dpnd => $dpnd_score,
		       score_dist => $dist_score,
		       score_word_anchor => $word_anchor_score,
		       score_dpnd_anchor => $dpnd_anchor_score,
		       q2score => $q2scores[$i]
	     });

	$result[-1]{verbose} = $e->{verbose} if $this->{store_verbose};
    }

    @result = sort {$b->{score_total} <=> $a->{score_total}} @result;

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{show_speed}) {
	printf ("@@@ %.4f sec. doc_list merging.\n", $conduct_time);
    }

    return \@result;
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
	    my $nums = $d->[4];
	    if (exists($did2pos{$did})) {
		my $j = $did2pos{$did};
		if (defined($offset)) {
		    push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, freq => $freq, fnum => $fnum, offset => $offset, nums => $nums});
		} else {
		    push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, freq => $freq});
		}
	    } else {
		if (defined($offset)) {
		    $serialized_docs->[$pos] = {did => $did, qid_freq => [{qid => $qid, freq => $freq, fnum => $fnum, offset => $offset, nums => $nums}]};
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

1;
