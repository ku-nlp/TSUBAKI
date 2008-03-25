#!/usr/bin/env perl

use strict;
use utf8;
use Indexer;
use Getopt::Long;
use KNP;
use KNP::Result;

my (%opt);
GetOptions(\%opt, 'syn');

binmode(STDIN,  ':encoding(euc-jp)');
binmode(STDOUT, ':encoding(euc-jp)');

my $buf;
while (<STDIN>) {
    $buf .= $_;
}

my $indexer = new Indexer( {ignore_yomi => 1});
# my $indice = ($opt{syn}) ? $indexer->makeIndexfromSynGraph($buf) : $indexer->makeIndexfromKnpResult($buf, {only_kihonkei => 1, with_kihonkei => 1, without_yomi => 1});
# my $indice = ($opt{syn}) ? $indexer->makeIndexfromSynGraph($buf) : $indexer->make_index_from_KNP_result_object($buf, {only_kihonkei => 1, with_kihonkei => 1, without_yomi => 1});

my $result = new KNP::Result($buf);
my $indice = $indexer->makeIndexFromKNPResult($result, {only_kihonkei => 1, with_kihonkei => 1, without_yomi => 1});

foreach my $e (@{$indice}) {
    printf("%s %.4f\n", $e->{rawstring}, $e->{freq}) if ($e->{isContentWord});
}
