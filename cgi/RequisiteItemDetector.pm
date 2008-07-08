package RequisiteItemDetector;

# $Id$

# 必須要素を自動検出するクラス


use strict;
use utf8;
use Encode;
use Data::Dumper;
use Configure;
use CompoundNounExtractor;

my $CONFIG = Configure::get_instance();

sub new {
    my ($class, $opt) = @_;

    my $this;
    $this->{threshold} = ($opt->{threshold}) ? $opt->{threshold} : 5;
    $this->{DFDB_OF_CNS} = ();

    bless $this;
}



sub getRequisiteDependencies {
    my ($this, $knpresult, $opt) = @_;

    $opt->{detect_compound_nouns} = 1;

    my %requisites = ();

    # データベースの遅延読み込み
    unless ($this->{DFDB_OF_CNS}) {
	tie %{$this->{DFDB_OF_CNS}}, 'CDB_File', $CONFIG->{COMPOUND_NOUN_DFDB_PATH} or die "$0: can't tie to $CONFIG->{COMPOUND_NOUN_DFDB_PATH} $!\n";
	$this->{CN_EXTRACTOR} = new CompoundNounExtractor({no_yomi_in_repname => $CONFIG->{IGNORE_YOMI}});
    }

    # 複合名詞の結合具合を計る
    foreach my $bnst ($knpresult->bnst) {
	my $cn = $this->{CN_EXTRACTOR}->ExtractCompoundNounfromBnst($bnst, { longest => 1 });
	next unless ($cn);

	my @reps = split(/\+/, $cn->{repname});
	for (my $i = 0; $i < scalar(@reps) - 1; $i++) {
	    my $a = $reps[$i];
	    my $b = $reps[$i + 1];

	    my $anob = $a . 'の' . $b;
	    my $anob_freq = $this->{DFDB_OF_CNS}{$anob};

	    my $rate = -1;
	    if ($anob_freq > 0) {
		my $ab_freq = $this->{DFDB_OF_CNS}{"$a$b"};
		$rate = $ab_freq / $anob_freq;
		next if ($rate < $this->{threshold});
	    }

	    $requisites{sprintf("%s->%s", $a, $b)} = 1;
	}
    }

    return \%requisites;
}

sub DESTROY {
    my ($this) = @_;
    untie %{$this->{DFDB_OF_CNS}};
}

1;
