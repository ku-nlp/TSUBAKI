package QueryKeyword;

#$Id$

# 1つの検索語を表すクラス

use strict;
use utf8;
use Encode;

# コンストラクタ
sub new {
    my ($class, $string, $sentence_flag, $is_phrasal_search, $near, $force_dpnd, $logical_cond_qkw, $syngraph, $opt) = @_;
    my $this = {
	words => [],
	dpnds => [],
	sentence_flag => $sentence_flag,
	is_phrasal_search => $is_phrasal_search,
	near => $near,
	force_dpnd => $force_dpnd,
	logical_cond_qkw => $logical_cond_qkw,
	rawstring => $string,
	syngraph => $syngraph
    };

    my $indice;
    my $knpresult = $opt->{knp}->parse($string);
    unless ($opt->{syngraph}) {
	# KNP 結果から索引語を抽出
	$indice = $opt->{indexer}->makeIndexfromKnpResult($knpresult->all);
    } else {
	# SynGraph 結果から索引語を抽出
 	$knpresult->set_id(0);
 	my $synresult = $opt->{syngraph}->OutputSynFormat($knpresult, $opt->{syngraph_option});
	$indice = $opt->{indexer}->makeIndexfromSynGraph($synresult);
    }

    # Indexer.pm より返される索引語を同じ代表表記ごとにまとめる
    my %buff;
    foreach my $k (keys %{$indice}){
	$buff{$indice->{$k}{group_id}} = [] unless (exists($buff{$indice->{$k}{group_id}}));
	push(@{$buff{$indice->{$k}{group_id}}}, $indice->{$k});
    }

    foreach my $group_id (sort {$buff{$a}->[0]{pos}[0] <=> $buff{$b}->[0]{pos}[0]} keys %buff) {
	my @word_reps;
	my @dpnd_reps;
	foreach my $m (@{$buff{$group_id}}) {
	    # 近接条件が指定されていない かつ 機能語 の場合は検索に用いない
	    next if ($m->{isContentWord} < 1 && $this->{is_phrasal_search} < 0);

	    if ($m->{rawstring} =~ /\-\>/) {
		push(@dpnd_reps, {string => $m->{rawstring}, qid => -1, freq => $m->{freq}, isContentWord => $m->{isContentWord}});
	    } else {
		push(@word_reps, {string => $m->{rawstring}, qid => -1, freq => $m->{freq}, isContentWord => $m->{isContentWord}});
	    }
	}
	push(@{$this->{words}}, \@word_reps) if (scalar(@word_reps) > 0);
	push(@{$this->{dpnds}}, \@dpnd_reps) if (scalar(@dpnd_reps) > 0);
    }

    if ($is_phrasal_search > 0) {
	$this->{near} = scalar(@{$this->{words}});
    }

    bless $this;
}

# デストラクタ
sub DESTROY {}

# 文字列表現を返すメソッド
sub to_string {
    my ($this) = @_;

    my $words_str = "WORDS:";
    foreach my $ws (@{$this->{words}}) {
	my $reps = "(";
	foreach my $w (@{$ws}) {
	    $reps .= "$w->{string}\[$w->{qid}] ";
	}
	chop($reps);
	$reps .= ")";
	$words_str .= " $reps";
    }

    my $dpnds_str = "DPNDS:";
    foreach my $ds (@{$this->{dpnds}}) {
	my $reps = "(";
	foreach my $d (@{$ds}) {
	    $reps .= "$d->{string}\[$d->{qid}] ";
	}
	chop($reps);
	$reps .= ")";
	$dpnds_str .= " $reps";
    }

    my $ret = "STRING: $this->{rawstring}\n";
    $ret .= ($words_str . "\n");
    $ret .= ($dpnds_str . "\n");
    $ret .= "LOGICAL_COND: $this->{logical_cond_qkw}\n";
    if ($this->{sentence_flag} > 0) {
	$ret .= "NEAR_SENT: $this->{near}\n";
    } else {
	$ret .= "NEAR_WORD: $this->{near}\n";
    }
    $ret .= "FORCE_DPND: $this->{force_dpnd}";

    return $ret;
}

1;
