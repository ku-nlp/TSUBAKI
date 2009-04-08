package Tsubaki::QueryAnalyzer;

# $Id$

use strict;
use utf8;
use Encode;
use Configure;

my $CONFIG = Configure::get_instance();


my $OPTIONAL = 'クエリ不要語';
my $DELETE = 'クエリ削除語';
my $DELETE_DPND = 'クエリ削除係り受け';
my $REQUISITE_DPND = 'クエリ必須係り受け';

sub new {
    my ($clazz, $option) = @_;
    my $this = {
	option => $option
    };


    bless $this;
}


sub analyze {
    my ($this, $knpresult, $opt) = @_;

    print qq(<H4 style="background-color:black; color:white;">クエリ処理</H4>\n) if ($this->{option}{debug});

    # 不要な動詞を検出する
    if ($opt->{telic_process}) {
	unless (defined $this->{cscf}) {
	    require CalcSimilarityByCF;

	    $this->{cscf} = new CalcSimilarityByCF();
	    $this->{cscf}->TieMIDBfile($CONFIG->{MIDB_PATH});
	}

	unless (defined $this->{antonyms}) {
	    $this->loadAntonymDB();
	}

	print qq(<H4 style="border-bottom: 2px solid black;">テリック処理</H4>\n) if ($this->{option}{debug});

	$opt->{threshold_of_telic_process} = 10 unless (defined $opt->{threshold_of_telic_process});
	$this->annotateTelicFeature($knpresult, {th => $opt->{threshold_of_telic_process}});
    }

    # つながりの強い複合名詞を検出する
    if ($opt->{CN_process}) {
	unless (defined $this->{DFDB_OF_CNS}) {
	    my $cdbfp = $CONFIG->{COMPOUND_NOUN_DFDB_PATH};
	    tie %{$this->{DFDB_OF_CNS}}, 'CDB_File', $cdbfp or die "$0: can't tie file $cdbfp $!\n";
	}

	print qq(<H4 style="border-bottom: 2px solid black;">複合名詞処理</H4>\n) if ($this->{option}{debug});

	$opt->{threshold_of_CN_process} = 5 unless (defined $opt->{threshold_of_CN_process});
	$this->annotateCompoundNounFeature($knpresult, {th => $opt->{threshold_of_CN_process}});
    }


    # NEを検出する
    if ($opt->{NE_process}) {
	print qq(<H4 style="border-bottom: 2px solid black;">固有表現処理</H4>\n) if ($this->{option}{debug});

	$this->annotateNEFeature($knpresult, $opt);
    }


    # NEの修飾句に含まれる語を検出する
    if ($opt->{modifier_of_NE_process}) {
	print qq(<H4 style="border-bottom: 2px solid black;">固有表現修飾句処理</H4>\n) if ($this->{option}{debug});

	$this->annotateNEmodifierFeature($knpresult, $opt);
    }






    # 削除する係り受けを検出する
    foreach my $kakarimoto ($knpresult->tag) {
	unless ($kakarimoto->fstring() =~ /$REQUISITE_DPND/) {
	    my $kakarisaki = $kakarimoto->parent();
	    next unless (defined $kakarisaki);

	    # 必須係り受けではなく、係り先・係り元のいずれかがクエリ削除語の場合は、その係り受けを削除する
	    if ($kakarimoto->fstring() =~ /$DELETE/ ||
		$kakarisaki->fstring() =~ /$DELETE/) {
		$kakarimoto->push_feature(($DELETE_DPND));
	    }
	}
    }
}



sub loadAntonymDB {
    my ($this) = @_;

    my %db = ();
    open (READER, '<:encoding(euc-jp)', $CONFIG->{ANTONYM_DIC_PATH}) or die "$!";
    while (<READER>) {
	chop;
	my ($e1, $e2) = split (/ /, $_);
	$e1 =~ s/:.+$//;
	$e2 =~ s/:.+$//;

	$db{$e1} = $e2;
    }
    close (READER);

    $this->{antonyms} = \%db;
}









######################################################################
#                           テリック処理
######################################################################

sub annotateTelicFeature {
    my ($this, $knpresult, $opt) = @_;

    foreach my $t ($knpresult->tag) {

	# 動詞 or サ変名詞かつ肯定表現のみ
	# 朝食を食べない子供の増加 -> 朝食の子供の増加 X
	if (($t->fstring =~ /<用言:動>/ || $t->fstring =~ /<サ変>/) && $t->fstring !~ /<否定表現>/) {
	    my ($verb) = ($t->fstring =~ /<正規化代表表記:([^>]+?)>/);
	    # 可能動詞の場合は原型を取得する
	    foreach my $mrph ($t->mrph) {
		$verb = $1 if ($mrph->fstring =~ /<可能動詞:([^>]+?)>/);
	    }

	    my $appendflag = 0;
	    if (defined $t->parent) {
		# 教える -> 先生
		foreach my $saki ($t->parent) {
		    foreach my $m ($saki->mrph) {
			next unless (defined $m->repname);

			$appendflag = $this->isWorthlessVerb($m, $verb, $opt);
		    }
		}
	    }

	    if (!$appendflag && defined $t->child) {
		# 体育 -> 教える
		foreach my $moto ($t->child) {
		    foreach my $m ($moto->mrph) {
			next unless (defined $m->repname);

			$appendflag = $this->isWorthlessVerb($m, $verb, $opt);
		    }
		}
	    }

	    if ($appendflag) {
		$t->push_feature(($OPTIONAL, 'テリック処理'));
	    }
	}
    }
}

sub isWorthlessVerb {
    my ($this, $mrph, $verb, $opt) = @_;

    my $noun = $mrph->repname;
    $noun = $1 if ($mrph->fstring =~ /<可能動詞:([^>]+?)>/);

    my ($rank, $score) = $this->getRankOfMI($noun, $verb);

    printf ("Y=%s N=%s score=%.2f, rank=%d (th=%d)<br>\n", $verb, $noun, $score, $rank, $opt->{th}) if ($this->{option}{debug});

    if ($score < 0 || $rank > $opt->{th}) {
	return 0;
    } else {
	# 反義語のチェック
	my $antonymV = $this->{antonyms}{$verb};
	if ($antonymV) {
	    my $N = 5;
	    my ($rank, $score) = $this->getRankOfMI($noun, $antonymV);

	    printf ("Y=%s N=%s score=%.2f, rank=%d (th=%d)<br>\n", $antonymV, $noun, $score, $rank, $N * $opt->{th}) if ($this->{option}{debug});

	    # 反義語が条件を満たす場合は省略しない
	    return ($score < 0 || $rank > ($N * $opt->{th})) ? 1 : 0;
	}
	return 1;
    }
}

sub getRankOfMI {
    my ($this, $noun, $verb) = @_;

    my $yogen = decode('utf8', $this->{cscf}->{mi}{$noun});
    my %buf;
    foreach my $y (split(/\|/, $yogen)) {
	my ($midasi, $score) = split(";", $y);
	my @dat = split(":", $midasi);
	$buf{$dat[0]} += $score;
    }

    my $rank = 0;
    my $score = -1;
    foreach my $k (sort {$buf{$b} <=> $buf{$a}} keys %buf) {
	$rank++;
	if ($k eq $verb) {
	    $score = $buf{$k};
	    last;
	}
    }

    return ($rank, $score);
}










######################################################################
#                   つながりの強い複合名詞を検出
######################################################################


sub annotateCompoundNounFeature {
    my ($this, $knpresult, $opt) = @_;

    # 複合名詞のつながりの強さを計る
    foreach my $bnst ($knpresult->bnst) {
	# 文節をまたいで複合名詞判定が行われないように、文節内の基本句をあらかじめ列挙
	my %buf = ();
	foreach my $tag ($bnst->tag) {
	    $buf{$tag} = 1;
	}

	foreach my $kakarimoto ($bnst->tag) {
	    my $kakarisaki = $kakarimoto->parent();
	    next unless (defined $kakarisaki);
	    next unless (exists $buf{$kakarisaki});

	    my $appendflag = 0;
	    if ($kakarimoto->fstring() =~ /一文字漢字/ &&
		$kakarisaki->fstring() =~ /一文字漢字/) {
		printf qq(%s -> %s %s (一文字漢字)<br>\n), ($kakarimoto->mrph)[0]->repname, ($kakarisaki->mrph)[0]->repname, $REQUISITE_DPND if ($this->{option}{debug});
		$appendflag = 1;
	    }
	    elsif ($this->isPhrase($kakarimoto, $kakarisaki, $opt)) {
		$appendflag = 1;
	    }

	    $kakarimoto->push_feature(($REQUISITE_DPND)) if ($appendflag);
	}
    }
}


sub isPhrase {
    my ($this, $kakarimoto, $kakarisaki, $opt) = @_;

    my $a = ($kakarimoto->mrph)[0];
    my $b = ($kakarisaki->mrph)[0];

    return 0 if ($a->fstring() !~ /<代表表記:.[^>]+?v>/ && $b->fstring() !~ /<複合\←>/);

    my ($a_rep) = ($a->repname =~ /(.+)\//);
    my ($b_rep) = ($b->repname =~ /(.+)\//);

    my @a_reps = ($a_rep);
    my @b_reps = ($b_rep);

    my $hasSyngraphAnnotation = $kakarimoto->synnodes;
    # SYNGRAPHの解析結果から抽出
    my $i = 0;
    my @buf = ();
    foreach my $kihonku (($kakarimoto, $kakarisaki)) {
	foreach my $synnodes ($kihonku->synnodes) {
	    foreach my $synnode ($synnodes->synnode) {
		my $midasi = $synnode->synid;
		next if ($midasi =~ /s\d+/);

		$midasi =~ s/(.+?)\/.+?([a|v])?$/\1/;
		push(@{$buf[$i]}, $midasi);
	    }
	}
	$i++;
    }

    push(@a_reps, @{$buf[0]}) if (defined $buf[0]);
    push(@b_reps, @{$buf[1]}) if (defined $buf[1]);

    foreach $a_rep (@a_reps) {
	foreach $b_rep (@b_reps) {
	    my $ab = sprintf ("%s%s", $a_rep, $b_rep);
	    my $anob = sprintf ("%sの%s", $a_rep, $b_rep);
	    my $anob_freq = $this->{DFDB_OF_CNS}{$anob} + 1;

	    my $ab_freq = $this->{DFDB_OF_CNS}{$ab} + 0;
	    my $rate = $ab_freq / $anob_freq;

	    printf "A=$a_rep B=$b_rep df(A no B) = $anob_freq df(A B) = $ab_freq RATE = %.1f (th=%d)<br>\n", $rate, $opt->{th} if ($this->{option}{debug});

	    return 1 if ($rate >= $opt->{th});
	}
    }

    return 0;
}









######################################################################
#                         固有表現を検出
######################################################################

# 固有表現内の係り受けに必須をつける
sub annotateNEFeature {
    my ($this, $knpresult, $opt) = @_;

    foreach my $bnst ($knpresult->bnst) {
	# 文節をまたいで複合名詞判定が行われないように、文節内の基本句をあらかじめ列挙
	my %buf = ();
	foreach my $tag ($bnst->tag) {
	    $buf{$tag} = 1;
	}

	foreach my $kakarimoto ($bnst->tag) {
	    my $kakarisaki = $kakarimoto->parent();
	    next unless (defined $kakarisaki);
	    next unless (exists $buf{$kakarisaki});

	    if ($kakarimoto->fstring() =~ /(<NE.+?>)/ &&
		$kakarisaki->fstring() =~ /(<NE.+?>)/) {

		printf qq(%s -> %s %s (NE内)<br>\n), ($kakarimoto->mrph)[0]->repname, ($kakarisaki->mrph)[0]->repname, $REQUISITE_DPND if ($this->{option}{debug});

		$kakarimoto->push_feature(($REQUISITE_DPND));
	    }
	}
    }
}










######################################################################
#                   固有表現の修飾句を検出
######################################################################

sub annotateNEmodifierFeature {
    my ($this, $knpresult, $opt) = @_;

    foreach my $kihonku (reverse $knpresult->tag) {
	next unless ($kihonku->fstring() =~ /(<NE.+?>)/);
	my $NEtag = $1;
	next if ($NEtag =~ /PERCENT|TIME|DATE|MONEY/);

	$this->setNEmodifier($kihonku);
    }

    foreach my $kihonku ($knpresult->tag) {
	if ($kihonku->fstring =~ /<固有表現を修飾>/) {

	    printf qq(%s %s (NEを修飾)<br>\n), ($kihonku->mrph)[0]->repname, $OPTIONAL if ($this->{option}{debug});
	    $kihonku->push_feature(($OPTIONAL));
	}
    }
}

sub setNEmodifier {
    my ($this, $kihonku, $opt) = @_;

    my @f = ('固有表現を修飾');
    foreach my $child ($kihonku->child) {
	next if ($child->fstring =~ /<NE.+?>/ ||
		 $child->fstring =~ /<固有表現を修飾>/);


	$child->push_feature(@f);
	$this->setNEmodifier($child, $opt);
    }
}

1;
