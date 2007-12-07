#!/usr/bin/env perl

use strict;
use utf8;
use Indexer;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'syn');

binmode(STDIN,  ':encoding(euc-jp)');
binmode(STDOUT, ':encoding(euc-jp)');

my $buf;
while (<STDIN>) {
    $buf .= $_;
}

my $indexer = new Indexer();
my $indice = ($opt{syn}) ? $indexer->makeIndexfromSynGraph($buf) : $indexer->makeIndexfromKnpResult($buf);

foreach my $e (@{$indice}) {
    print $e->{midashi} . "\n" if ($e->{isContentWord});
}
