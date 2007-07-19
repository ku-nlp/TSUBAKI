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
	KNP => new KNP(-Command => "$opts->{KNP_PATH}/knp",
		       -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
		       -JumanCommand => "$opts->{JUMAN_PATH}/juman"),
	SYNGRAPH => new SynGraph($opts->{SYNDB_PATH}),
	SYNGRAPH_OPTION => {relation => 1, antonym => 1, hypocut_attachnode => 9}
    };

    # ストップワードの処理
    if ($opts->{STOP_WORDS}) {
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
    else {
	$this->{INDEXER} = new Indexer();
    }

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
	my $sentence_flag = -1;
	## フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/){
	    $near = 0;
	    $q_str = $1;
	}

	## 近接検索かどうかの判定
	if ($q_str =~ /^(.+)?~(.+)$/){
	    $q_str = $1;
	    my $constraint_tag = $2;
	    if ($constraint_tag =~ /^(\d+)(W|S)$/) {
		$logical_cond_qkw = 'AND';
		$near = $1;
		$sentence_flag = 1 if ($2 eq 'S');
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
	if ($opt->{syngraph} > 0) {
	    $q= new QueryKeyword($q_str, $sentence_flag, $near, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}, syngraph => $this->{SYNGRAPH}, syngraph_option => $this->{SYNGRAPH_OPTION}});
	} else {
	    $q= new QueryKeyword($q_str, $sentence_flag, $near, $force_dpnd, $logical_cond_qkw, $opt->{syngraph}, {knp => $this->{KNP}, indexer => $this->{INDEXER}});
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
