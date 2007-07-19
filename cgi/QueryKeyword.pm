package QueryKeyword;

use strict;
use utf8;
use Encode;

sub new {
    my ($class, $string, $sentence_flag, $near, $force_dpnd, $logical_cond_qkw, $syngraph, $opt) = @_;
    my $this = {
	words => [],
	dpnds => [],
	sentence_flag => $sentence_flag,
	near => $near,
	force_dpnd => $force_dpnd,
	logical_cond_qkw => $logical_cond_qkw,
	rawstring => $string,
	syngraph => $syngraph
    };

    my $indice;
    my $knpresult = $opt->{knp}->parse($string);
    unless ($opt->{syngraph}) {
	$indice = $opt->{indexer}->makeIndexfromKnpResult($knpresult->all);
    } else {
 	$knpresult->set_id(0);
 	my $synresult = $opt->{syngraph}->OutputSynFormat($knpresult, $opt->{syngraph_option});
	$indice = $opt->{indexer}->makeIndexfromSynGraph($synresult);
    }

    my %buff;
    foreach my $k (keys %{$indice}){
	$buff{$indice->{$k}{group_id}} = [] unless (exists($buff{$indice->{$k}{group_id}}));
	push(@{$buff{$indice->{$k}{group_id}}}, $indice->{$k});
    }

    foreach my $group_id (sort {$buff{$a}->[0]{pos}[0] <=> $buff{$b}->[0]{pos}[0]} keys %buff) {
	my @word_reps;
	my @dpnd_reps;
	foreach my $m (@{$buff{$group_id}}) {
	    next if ($m->{isContentWord} < 1 && $this->{near} < 0);

	    if ($m->{rawstring} =~ /\-\>/) {
		push(@dpnd_reps, {string => $m->{rawstring}, qid => -1, freq => $m->{freq}, isContentWord => $m->{isContentWord}});
	    } else {
		push(@word_reps, {string => $m->{rawstring}, qid => -1, freq => $m->{freq}, isContentWord => $m->{isContentWord}});
	    }
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
