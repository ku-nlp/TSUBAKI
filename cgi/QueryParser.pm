package QueryParser;

#$id$

# 検索クエリを内部形式に変換するクラス

use strict;
use Encode;
use utf8;
use Unicode::Japanese;
use KNP;
use Indexer;
use SynGraph;
use QueryKeyword;

# コンストラクタ
sub new {
    my ($class, $opts) = @_;
    my $this = {
	KNP => new KNP(-Command => "$opts->{KNP_PATH}/knp",
		       -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
		       -JumanCommand => "$opts->{JUMAN_PATH}/juman"),
	SYNGRAPH => new SynGraph($opts->{SYNDB_PATH}),
	SYNGRAPH_OPTION => {relation => 1, antonym => 1, hypocut_attachnode => 9}
    };

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

    bless $this;
}

# 検索クエリを解析
sub parse {
    my ($this, $qks_str, $opt) = @_;

    my @qks = ();
    my %wbuff = ();
    my %dbuff = ();

    ## 空白で区切る
    foreach my $q_str (split(/(?: |　)+/, $qks_str)) {
	my $near = -1;
	my $logical_cond_qkw = 'AND'; # 検索語に含まれる単語間の論理条件
	my $force_dpnd = -1;
	my $sentence_flag = -1;
	my $phrasal_flag = -1;
	# フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/){
	    $phrasal_flag = 1;
	    $q_str = $1;

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
	    if ($constraint_tag =~ /^(\d+)(W|S)$/) {
		# 近接制約
		$logical_cond_qkw = 'AND';
		$near = $1;
		$sentence_flag = 1 if ($2 eq 'S');
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
	    $q= new QueryKeyword($q_str, $sentence_flag, $phrasal_flag, $near, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}, syngraph => $this->{SYNGRAPH}, syngraph_option => $this->{SYNGRAPH_OPTION}});
	} else {
	    $q= new QueryKeyword($q_str, $sentence_flag, $phrasal_flag, $near, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}});
	}

	push(@qks, $q);
    }

    my $qid = 0;
    my %qid2rep = ();
    my %qid2qtf = ();
    my %rep2qid = ();
    my %dpnd_map = ();
    # 検索語中の各索引語にIDをふる
    foreach my $qk (@qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{qid} = $qid;
		$rep2qid{$rep->{string}} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid2qtf{$qid} = $rep->{freq};
		$qid++;
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{qid} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid2qtf{$qid} = $rep->{freq};
		my ($kakarimoto, $kakarisaki) = split('->', $rep->{string});
		push(@{$dpnd_map{$rep2qid{$kakarimoto}}}, {kakarisaki_qid => $rep2qid{$kakarisaki}, dpnd_qid => $qid});
		$qid++;
	    }
	}
    }
	
    # 検索クエリを表す構造体
    my $ret = {
	keywords => \@qks,
	logical_cond_qk => $opt->{logical_cond_qk},
	only_hitcount => $opt->{only_hitcount},
	qid2rep => \%qid2rep,
	qid2qtf => \%qid2qtf,
	dpnd_map => \%dpnd_map
    };
    return $ret;
}

# デストラクタ
sub DESTROY {}

1;
