package TsubakiEngine4OrdinarySearch;

# $Id$

# 通常の検索を行うクラス

use strict;
use Retrieve;
use utf8;

# TsubakiEngine を継承する
use TsubakiEngine;
@TsubakiEngine4OrdinarySearch::ISA = qw(TsubakiEngine);


sub new {
    my ($class, $opts) = @_;
    my $obj = $class->SUPER::new($opts);

    # DAT ファイルから単語を含む文書を検索する retriever オブジェクトをセットする
    $obj->{word_retriever} = new Retrieve($opts->{idxdir}, 'word', $opts->{skip_pos}, $opts->{verbose}, $opts->{show_speed});

    # DAT ファイルから係り受けを含む文書を検索する retriever オブジェクトをセットする
    $obj->{dpnd_retriever} = new Retrieve($opts->{idxdir}, 'dpnd', $opts->{skip_pos}, $opts->{verbose}, $opts->{show_speed});

    bless $obj;
}

sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $qid2df, $cal_method, $qid2qtf, $dpnd_map, $qid2gid, $dpnd_on, $dist_on) = @_;

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

		    # 関数化するよりも高速
		    my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
		    my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
		    my $score = $tff * $idf;
		    $qid2poslist{$qid} = $this->{word_retriever}->load_position($qid_freq->{fnum}, $qid_freq->{offset}, $qid_freq->{nums});

		    print "did=$did qid=$qid tf=$tf df=$df qtf=$qtf length=$dlength score=$score\n" if ($this->{verbose});

		    $merged_docs[$i]->{word_score} += $score * $qtf;
		    $q2scores[$i]->{word}{$qid} = {tf => $tf, qtf => $qtf, df => $df, dlength => $dlength, score => $score * $qtf};
		    push @{$merged_docs[$i]->{verbose}}, { qid => $qid, tf => $tf, df => $df, length => $dlength, score => $score} if $this->{store_verbose};
		}

		foreach my $qid (keys %$dpnd_map) {
		    foreach my $e (@{$dpnd_map->{$qid}}) {
			my $dpnd_qid = $e->{dpnd_qid};
			my $kakarisaki_qid = $e->{kakarisaki_qid};
			my $dlength = $d_length_buff{$did};

			my $dist = $this->get_minimum_distance($qid2poslist{$qid}, $qid2poslist{$kakarisaki_qid}, $dlength);
			if ($dist > 30) {
			    $merged_docs[$i]->{near_score}{$dpnd_qid} = 0;
			} else {
			    my $tf = (30 - $dist) / 30;
			    my $df = $qid2df->{$dpnd_qid};
			    my $qtf = $qid2qtf->{$dpnd_qid};

			    my $score;
			    # 検索クエリに含まれる係り受けが、ドキュメント集合に一度も出てこない場合
			    if ($df == -1) {
				$score = 0;
			    }
			    else {
				my $tff = (3 * $tf) / ((0.5 + 1.5 * $dlength / $this->{AVERAGE_DOC_LENGTH}) + $tf);
				my $idf = log(($this->{TOTAL_NUMBUER_OF_DOCS} - $df + 0.5) / ($df + 0.5));
				$score = $qtf * $tff * $idf;
			    }

			    $q2scores[$i]->{near}{$qid} = {dist => $dist, qtf => $qtf, df => $df, dlength => $dlength, score => $score, kakarisaki_qid => $kakarisaki_qid};
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

    my @result;
    for (my $i = 0; $i < @merged_docs; $i++) {
	my $e = $merged_docs[$i];
	my $score = $e->{word_score};
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

	    printf ("did=%09d qid=%02d w=%.3f d=%.3f n=%.3f total=%.3f\n", $e->{did}, $qid, $e->{word_score}, $e->{dpnd_score}{$qid}, $score_of_qid, $score) if ($this->{verbose});
	}
	print "-----\n" if ($this->{verbose});

	push(@result, {did => $e->{did},
		       score_total => $score,
		       score_word => $e->{word_score},
		       score_dpnd => $dpnd_score,
		       score_dist => $dist_score,
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
