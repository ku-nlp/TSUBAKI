package QueryFilter;

# $Id;$


use strict;
use utf8;
use Encode;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
use CalcSimilarityByCF;
use Configure;

my $CONFIG = Configure::get_instance();


sub new {
    my ($clazz, $option) = @_;
    my $this = {
	option => $option,
	cscf => new CalcSimilarityByCF()
    };

    $this->{cscf}->TieMIDBfile($CONFIG->{MIDB_PATH});

    bless $this;
}

sub getMidasiWithoutYomi {
    my ($word) = @_;

    my $word_wo_yomi;
    my @buf;
    foreach my $cand (split(/\?/, $word)) {
	my ($hyouki, $yomi) = split(/\//, $cand);
	push(@buf, $hyouki);
    }

    return join("?", @buf);
}

sub filterOutWorthlessVerbs {
    my ($this, $knpresult, $opt) = @_;

    my %worthlessVerbs = ();
    my %additionalDpnds = ();
    foreach my $t ($knpresult->tag) {

	# 動詞かつ肯定表現のみ
	# 朝食を食べない子供の増加 -> 朝食の子供の増加 X
	if ($t->fstring =~ /<用言:動>/ && $t->fstring !~ /<否定表現>/) {
	    my ($verb) = ($t->fstring =~ /<正規化代表表記:([^>]+?)>/);
	    next unless (defined $t->parent);

	    my $flag = 0;
	    # 教える -> 先生
	    foreach my $saki ($t->parent) {
		foreach my $m ($saki->mrph) {
		    next unless (defined $m->repname);

		    if ($this->isWorthlessVerb($m, $verb, $opt)) {
			$flag = 1;
			my @children = $t->child;
			&registBuffer(\%worthlessVerbs, \%additionalDpnds, $verb, \@children, $m->repname, {ignore_yomi => $opt->{ignore_yomi}, kakarisaki => 1});
		    }
		}
	    }
	    next if ($flag);

	    # 体育 -> 教える
	    foreach my $moto ($t->child) {
		foreach my $m ($moto->mrph) {
		    next unless (defined $m->repname);

		    if ($this->isWorthlessVerb($m, $verb, $opt)) {
			my @parents = $t->parent;
			&registBuffer(\%worthlessVerbs, \%additionalDpnds, $verb, \@parents, $m->repname, {ignore_yomi => $opt->{ignore_yomi}, kakarisaki => 0});
		    }
		}
	    }
	}
    }

    return (\%worthlessVerbs, \%additionalDpnds);
}


sub isWorthlessVerb {
    my ($this, $mrph, $verb, $opt) = @_;

    my ($rank, $score) = $this->getRankOfMI($mrph, $verb);
    return ($score < 0 || $rank > $opt->{th}) ? 0 : 1;
}

sub registBuffer {
    my ($worthlessVerbs, $additionalDpnds, $verb, $pivot, $m, $opt) = @_;

    if ($opt->{ignore_yomi}) {
	$verb = &getMidasiWithoutYomi($verb);
	$m = &getMidasiWithoutYomi($m);
    }

    foreach my $p (@$pivot) {
	my ($noun) = ($p->fstring =~ /<正規化代表表記:([^>]+?)>/);
	$noun = &getMidasiWithoutYomi($noun) if ($opt->{ignore_yomi});
	$worthlessVerbs->{$verb}++;

	if ($opt->{kakarisaki}) {
	    $additionalDpnds->{sprintf("%s->%s", $noun, $m)}++;
	} else {
	    $additionalDpnds->{sprintf("%s->%s", $m, $noun)}++;
	}
    }
}

sub getRankOfMI {
    my ($this, $mrph, $verb) = @_;

    my $yogen = decode('utf8', $this->{cscf}->{mi}{$mrph->repname});
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

1;
