#!/usr/bin/env perl

# $Id;$

##################################################################
# インデックスデータから文書長DB(Storable形式)を作成するプログラム
##################################################################

use strict;
use utf8;
use Getopt::Long;
use Storable;

my (%opt); GetOptions(\%opt, 'z');

my $fp = shift(@ARGV);
if (!$fp) {
    print "Usage $0 idxfile [z]\n";
    exit;
}

my %doc_length = ();
if ($opt{z}) {
    open(READER, "zcat $fp |") or die;
} else {
    open(READER, $fp) or die;
}
binmode(READER, ":utf8");

while (<READER>) {
    next if (index($_, '->') > 0);

    chop($_);
    my ($word, @did_freqs) = split(' ', $_);

    foreach my $did_freq (@did_freqs) {
	my ($did, $freq) = split(':', $did_freq);
	my ($freq, $pos) = split('@', $freq);

	$doc_length{$did} += $freq;
    }
}
close(READER);
$fp =~ s/.idx(.gz)?$//;
store(\%doc_length, "$fp.doc_length.bin") or die;
