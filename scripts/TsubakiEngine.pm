package TsubakiEngine;

use strict;
use IO::Socket;
use Retrieve;
use Indexer qw(makeIndexfromKnpResult makeIndexfromJumanResult);
use Encode qw(from_to encode decode);
use URI::Escape;
use Storable qw(store retrieve);
use utf8;
use CDB_File;
use Data::Dumper;
# use Devel::Size qw(total_size);
# use Getopt::Long;
use OKAPI;
use Devel::Size qw/size total_size/;



# my (%opt); GetOptions(\%opt, 'dfdbdir=s', 'idxdir=s', 'port=s', 'skip_pos', 'debug');

# host名を得る
my $host = `hostname`; chop($host);


binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");

sub new {
    my ($class, $opts) = @_;
    my $this = {
	word_retriever => new Retrieve($opts->{idxdir}, 'word', $opts->{skip_pos}, $opts->{verbose}),
	dpnd_retriever => new Retrieve($opts->{idxdir}, 'dpnd', $opts->{skip_pos}, $opts->{verbose}),
	DOC_LENGTH_DBs => [],
	AVERAGE_DOC_LENGTH => $opts->{average_doc_length},
	TOTAL_NUMBUER_OF_DOCS => $opts->{total_number_of_docs},
	verbose => $opts->{verbose},
	dlengthdb_hash => $opts->{dlengthdb_hash}
    };

    opendir(DIR, $opts->{dlengthdbdir});
    foreach my $dbf (readdir(DIR)) {
	next unless ($dbf =~ /doc_length\.bin/);
	
	my $fp = "$opts->{dlengthdbdir}/$dbf";

	my $dlength_db;
	# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
	if ($opts->{dlengthdb_hash}) {
	    tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	}
	else {
	    $dlength_db = retrieve($fp) or die;
	}

	push(@{$this->{DOC_LENGTH_DBs}}, $dlength_db);
    }
    closedir(DIR);

    bless $this;
}	    

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

    my ($alldocs_word, $alldocs_dpnd) = $this->retrieve_documents($query);
    
#    printf "alldocs_word %d Byte.\n", (total_size($alldocs_word));
#    printf "alldocs_dpnd %d Byte.\n", (total_size($alldocs_dpnd));

#    print "*** dump ***\n";
#    print Dumper($alldocs_word);
#    print "*** dump ***\n";

    my $cal_method;
    if ($query->{only_hitcount}) {
	$cal_method = undef; # ヒットカウントのみの場合はスコアは計算しない
    } else {
	$cal_method = new OKAPI($this->{AVERAGE_DOC_LENGTH}, $this->{TOTAL_NUMBUER_OF_DOCS});
    }

    my $doc_list = $this->merge_docs($alldocs_word, $alldocs_dpnd, $qid2df, $cal_method);

    return $doc_list;
}

## 単語を含む文書の検索
sub retrieve_from_dat {
    my ($retriever, $reps, $doc_buff, $add_flag, $position) = @_;

    ## 代表表記化／SynGraph により複数個の索引に分割された場合の処理 (かんこう -> 観光 OR 刊行 OR 敢行 OR 感光 を検索する)
    my @results;
    foreach my $rep (@{$reps}) {
	# ※ 文書数が ldf より 1 多い
	# print $rep . " " . scalar(@{$results[-1]}) . "\n";

	# rep は構造体
	# rep = {qid, string}
	push(@results, $retriever->search($rep, $doc_buff, $add_flag, $position));
    }

    # ※ クエリが重なったときの対応について考える
    my $ret = &serialize(\@results);

#   print scalar(@$ret) . "\n";
    return $ret;
}

sub merge_docs {
    my ($this, $alldocs_words, $alldocs_dpnds, $qid2df, $cal_method) = @_;
    my %did2pos = ();

    my $pos = 0;
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
				$dlength = $db->[$did % 1000000];
				if (defined($dlength)) {
				    $d_length_buff{$did} = $dlength;
				    last;
				}
			    }
			}
		    }
		    my $score = $cal_method->calculate_score({tf => $tf, df => $df, length => $dlength});
		    print "did=$did qid=$qid tf=$tf df=$df length=$dlength score=$score\n" if $this->{verbose};
		    $merged_docs[$i]->{score} += $score;
		}
#		print "-----\n";
	    }
	}
    }

    return \@merged_docs unless (defined($cal_method));

    foreach my $docs_dpnd (@{$alldocs_dpnds}) {
	foreach my $doc (@{$docs_dpnd}) {
	    my $did = $doc->{did};
	    if (exists($did2pos{$did})) {
		my $i = $did2pos{$did};
		
		my $tf = $doc->{freq};
		my $df = 1; # ※
		my $dlength = $d_length_buff{$did};
		$merged_docs[$i]->{score} += $cal_method->calculate_score({tf => $tf, df => $df, doc_length => $dlength});
	    }
	}
    }

    @merged_docs = sort {$b->{score} <=> $a->{score}} @merged_docs;
    return \@merged_docs;
}

sub retrieve_documents {
    my ($this, $query) = @_;
    #input,$ranking_method,$logical_cond,$sf_level,$dpnd_condition,$required_results,$near, ) = @_;

    # 文書の取得
    my $alldocs_word = [];
    my $alldocs_dpnd = [];
    my $doc_buff = {};
    my $add_flag = 1;
    foreach my $keyword (@{$query->{keywords}}) {
	print $keyword->{rawstring} . "\n" if ($this->{verbose});
	my $docs_word = [];
	my $docs_dpnd = [];
	# keyword中の単語を含む文書の検索
	foreach my $reps_of_word (@{$keyword->{words}}) {
	    my $docs = &retrieve_from_dat($this->{word_retriever}, $reps_of_word, $doc_buff, $add_flag, $keyword->{near});
#	    printf "docs %d Byte.\n", (total_size($docs));

	    $add_flag = 0 if ($add_flag > 0);

	    # 各語について検索された結果を納めた配列に push
	    push(@{$docs_word}, $docs);
	}

	# keyword中の係受けを含む文書の検索
	foreach my $reps_of_dpnd (@{$keyword->{dpnds}}) {
	    my $docs = &retrieve_from_dat($this->{dpnd_retriever}, $reps_of_dpnd, $doc_buff, $add_flag, $keyword->{near});

	    # 各係受けについて検索された結果を納めた配列に push
	    push(@{$docs_dpnd}, $docs);
	}
	
	# 近接・フレーズ制約の適用
#	if ($keyword->{near} > -1) {
#	    $docs_word = &intersect_wo_hash($docs_word, $keyword->{near});
#	}

	# 係受け制約の適用 ※
#	if ($keyword->{force_dpnd}) {
#	    $docs_word = &intersect_wo_hash($docs_word, $keyword->{near});
#	}

	# 検索キーワードごとに検索された文書の配列へpush
	push(@{$alldocs_word}, &serialize(&intersect_wo_hash($docs_word, $keyword->{near}))); # クエリ中の単語間の論理演算をとる場合は変更
	push(@{$alldocs_dpnd}, &serialize(&intersect_wo_hash($docs_dpnd, 0)));
    }
    
    # 論理条件にしたがい文書のマージ
    if ($query->{logical_cond} eq 'AND') {
	$alldocs_word =  &intersect_wo_hash($alldocs_word, 0);
    } else {
	# 何もしなければ OR
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
	    next unless (defined($d)); # ※本来なら空はないはず

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

sub intersect_wo_hash {
    my ($docs, $near) = @_;

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

	    if ($flag < 1){
		push(@{$results[0]}, $sorted_docs[0]->[$i]);
		for (my $j = 1; $j < scalar(@sorted_docs); $j++) {
		    push(@{$results[$j]}, $sorted_docs[$j]->[0]);
		}
	    }
	}
    }

    return \@results if($near < 1);

    my @new_results = ();
    for(my $i = 0; $i < scalar(@results); $i++){
	$new_results[$i] = [];
    }

    # クエリの順序でソート
#   @results = sort{$a->[0]{qid} <=> $b->[0]{qid}} @results;

    for (my $d = 0; $d < scalar(@{$results[0]}); $d++) {
	my @poslist = ();
	# クエリ中の単語の出現位置リストを作成
	for (my $q = 0; $q < scalar(@results); $q++) {
	    foreach my $p (@{$results[$q]->[$d]->{pos}}) {
		push(@{$poslist[$q]}, $p);
	    }
	}

	while (scalar(@{$poslist[0]}) > 0) {
	    my $flag = 0;
	    my $pos = shift(@{$poslist[0]}); # クエリ中の先頭の単語の出現位置
	    for (my $q = 1; $q < scalar(@poslist); $q++) {
		while (1) {
		    # クエリ中の単語の出現位置リストが空なら終了
		    if (scalar(@{$poslist[$q]}) < 1) {
			$flag = 1;
			last;
		    }

		    if ($pos < $poslist[$q]->[0] && $poslist[$q]->[0] < $pos + $near + 2) {
			$flag = 0;
			last;
		    } elsif ($poslist[$q]->[0] < $pos) {
			shift(@{$poslist[$q]});
		    } else {
			$flag = 1;
			last;
		    }
		}

		last if ($flag > 0);
		$pos = $poslist[$q]->[0];
	    }

	    if ($flag == 0) {
		for (my $q = 0; $q < scalar(@results); $q++) {
		    push(@{$new_results[$q]}, $results[$q]->[$d]);
		}
	    }
	}
    }

    return \@new_results;
}
