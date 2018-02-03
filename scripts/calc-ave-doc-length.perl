#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Getopt::Long;
use Storable;

my (%opt); GetOptions(\%opt, 'txt');

my $N = 0;
my $total = 0;

foreach my $file (@ARGV) {
    if ($opt{txt}) {
	open(READER, $file) or die;
	while (<READER>) {
	    chop($_);
	    my ($did, $length) = split;
	    $N++;
	    $total += $length;
	}
	close(READER); 
    }
    else {
	my $bin = retrieve($file) or die "$!";
	while (my ($did, $length) = each %$bin) {
	    $N++;
	    $total += $length;
	}
    }
}

printf "num of docs: %d\n", $N;
printf "ave doc length: %d\n", ($total / $N);
