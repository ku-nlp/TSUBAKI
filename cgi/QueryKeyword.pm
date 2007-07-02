package QueryKeyword;

use strict;
use utf8;
use Encode;

sub new {
    my ($class, $string, $near, $opt) = @_;
    my $this = {
	words => [],
	dpnds => [],
	near => $near,
	rawstring => $string
    };

    my $indice;
    my $knpresult = $opt->{knp}->parse($string);
    unless ($opt->{syngraph}) {
	$indice = $opt->{indexer}->makeIndexfromKnpResult($knpresult->all);
    } else {
	print STDERR "Error :: Not Supported SynGraph Indice.\n";
	exit;

 	$knpresult->set_id(0);
 	my $synresult = $opt->{syngraph}->OutputSynFormat($knpresult, {relation => 1, antonym => 1});
 	my $s_all = $synresult;
	print encode('euc-jp', $s_all);
	$indice = $opt->{indexer}->makeIndexfromSynGraph($synresult);
    }

    my %buff;
    foreach my $k (keys %{$indice}){
	# 代表表記化により展開された索引語をまとめる
	$buff{$indice->{$k}{group_id}} = [] unless (exists($buff{$indice->{$k}{group_id}}));
	push(@{$buff{$indice->{$k}{group_id}}}, $indice->{$k});
    }

    foreach my $group_id (sort {$buff{$a}->[0]{pos}[0] <=> $buff{$b}->[0]{pos}[0]} keys %buff) {
	my @word_reps;
	my @dpnd_reps;
	foreach my $m (@{$buff{$group_id}}){
	    next if ($m->{isContentWord} < 1 && $this->{near} < 0);
	    ($m->{rawstring} =~ /\-\>/) ? push(@dpnd_reps, $m->{rawstring}) : push(@word_reps, $m->{rawstring});
	}
	push(@{$this->{words}}, \@word_reps) if (scalar(@word_reps) > 0);
	push(@{$this->{dpnds}}, \@dpnd_reps) if (scalar(@dpnd_reps) > 0);
    }

    bless $this;
}

sub DESTROY {}

sub to_string {
    my ($this) = @_;

    my $words_str = "WORDS:";
    foreach my $ws (@{$this->{words}}) {
	my $reps = "(";
	foreach my $w (@{$ws}) {
#	    $reps .= "$w->{rawstring} ";
	    $reps .= "$w ";
	}
	chop($reps);
	$reps .= ")";
	$words_str .= " $reps";
    }

    my $dpnds_str = "DPNDS:";
    foreach my $ds (@{$this->{dpnds}}) {
	my $reps = "(";
	foreach my $d (@{$ds}) {
#	    $reps .= "$d->{rawstring} ";
	    $reps .= "$d ";
	}
	chop($reps);
	$reps .= ")";
	$dpnds_str .= " $reps";
    }

    my $ret = "STRING: $this->{rawstring}\n";
    $ret .= ($words_str . "\n");
    $ret .= ($dpnds_str . "\n");
    $ret .= "NEAR: $this->{near}";

    return $ret;
}

1;
