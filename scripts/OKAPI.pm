package OKAPI;

use strict;
use utf8;

sub new {
    my ($class, $average_doc_length, $N) = @_;
    my $this = {
	method_name => 'OKAPI_BM25',
	average_doc_length => $average_doc_length,
	total_number_of_docs => $N
    };

    bless $this;
}

sub DESTROY {};

sub calculate_score {
    my ($this, $args) = @_;

    my $freq = $args->{tf};
    my $gdf = $args->{gdf};
    my $length = $args->{length};

    my $tf = (3 * $freq) / ((0.5 + 1.5 * $length / $this->{average_doc_length}) + $freq);
    my $idf =  log(($this->{total_number_of_docs} - $gdf + 0.5) / ($gdf + 0.5));

    return $tf * $idf;
}

1;
