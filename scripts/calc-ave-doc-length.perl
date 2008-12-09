#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Storable;

my $N = 0;
my $total = 0;

foreach my $file (@ARGV) {
    my $bin = retrieve($file) or die "$!";
    while (my ($did, $length) = each %$bin) {
	$N++;
	$total += $length;
    }
}

printf "num of docs: %d\n", $N;
printf "ave doc length: %.3f\n", ($total / $N);
