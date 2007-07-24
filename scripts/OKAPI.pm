package OKAPI;

use strict;
use utf8;

# コンストラクタ
sub new {
    my ($class, $average_doc_length, $N, $debug) = @_;
    my $this = {
	method_name => 'OKAPI_BM25',
	average_doc_length => $average_doc_length,
	total_number_of_docs => $N,
	debug => $debug
    };

    bless $this;
}

# デストラクタ
sub DESTROY {};

# 文書のスコアを計算するメソッド
sub calculate_score {
    my ($this, $args) = @_;

    my $freq = $args->{tf};
    my $gdf = $args->{df};
    my $length = $args->{length};

    return -1 if ($freq <= 0 || $gdf <= 0 || $length <= 0);

    my $tf = (3 * $freq) / ((0.5 + 1.5 * $length / $this->{average_doc_length}) + $freq);
    my $idf =  log(($this->{total_number_of_docs} - $gdf + 0.5) / ($gdf + 0.5));

    print "log(($this->{total_number_of_docs} - $gdf + 0.5) / ($gdf + 0.5))\n" if ($this->{debug});

    return $tf * $idf;
}

1;
