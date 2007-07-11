package QueryParser;

# 検索クエリを内部形式に変換するモジュール
# my $TOOL_HOME='/home/skeiji/local/bin';

use strict;
use Encode;
use utf8;
use Unicode::Japanese;
use KNP;
use Indexer;
use SynGraph;
use QueryKeyword;

sub new {
    my ($class, $opts) = @_;
    my $this = {
	INDEXER => new Indexer(),
	KNP => new KNP(-Command => "$opts->{KNP_PATH}/knp",
		       -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
		       -JumanCommand => "$opts->{JUMAN_PATH}/juman"),
	SYNGRAPH => new SynGraph($opts->{SYNDB_PATH}),
	SYNGRAPH_OPTION => $opts->{SYNGRAPH_OPTION} ? $opts->{SYNGRAPH_OPTION} : {relation => 1, antonym => 1}
    };

    bless $this;
}

sub parse {
    my ($this, $qks_str, $opt) = @_;

    ## 空白で区切る
    my @qks = ();
    my %wbuff = ();
    my %dbuff = ();

    foreach my $q_str (split(/(?: |　)+/, $qks_str)) {
	my $near = -1;
	my $logical_cond_qkw = 'AND';
	my $force_dpnd = -1;

	## フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/){
	    $near = 1;
	    $q_str = $1;
	}

	## 近接検索かどうかの判定
	if ($q_str =~ /^(.+)?~(.+)$/){
	    $q_str = $1;
	    my $constraint_tag = $2;
	    if ($constraint_tag =~ /^(\d+)$/) {
		$logical_cond_qkw = 'AND';
		$near = $1;
	    } elsif ($constraint_tag =~ /(AND|OR)/) {
		$logical_cond_qkw = $1;
	    } elsif ($constraint_tag =~ /FD/) {
		$logical_cond_qkw = 'AND';
		$force_dpnd = 1;
	    }
	}

	## 半角アスキー文字列を全角に置換する
	$q_str = Unicode::Japanese->new($q_str)->h2z->getu;
	my $q;
	if ($opt->{syngraph}) {
	    $q= new QueryKeyword($q_str, $near, $force_dpnd, $logical_cond_qkw, {knp => $this->{KNP}, indexer => $this->{INDEXER}, syngraph => $this->{SYNGRAPH}, syngraph_option => $this->{SYNGRAPH_OPTION}});
	} else {
	    $q= new QueryKeyword($q_str, $near, $force_dpnd, $logical_cond_qkw, {knp => $this->{KNP}, indexer => $this->{INDEXER}});
	}

	push(@qks, $q);
    }

    my $qid = 0;
    my %qid2rep = ();
    my %qid2qtf = ();
    foreach my $qk (@qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{qid} = $qid;
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
		$qid++;
	    }
	}
    }
	
    return {keywords => \@qks, logical_cond_qk => $opt->{logical_cond_qk}, only_hitcount => $opt->{only_hitcount}, qid2rep => \%qid2rep, qid2qtf => \%qid2qtf};
}

sub DESTROY {
    my ($this) = @_;
#     foreach my $cdb (@{$this->{DF_WORD_DBs}}) {
# 	untie %{$cdb};
#     }
#     foreach my $cdb (@{$this->{DF_DPND_DBs}}) {
# 	untie %{$cdb};
#     }
}

1;
