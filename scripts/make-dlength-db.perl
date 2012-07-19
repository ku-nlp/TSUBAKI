#!/usr/bin/env perl

# $Id$

##################################################################
# インデックスデータから文書長DB(Storable形式)を作成するプログラム
##################################################################

# -txt: Storable形式ではなくtxt形式で出力

use strict;
use utf8;
use Getopt::Long;
use Storable;

my (%opt); GetOptions(\%opt, 'z', 'txt');

foreach my $fp (@ARGV) {
    if (!$fp) {
	print "Usage $0 idxfile [-z] [-txt]\n";
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
	next unless (index($_, '*') > 0);
# 	next if (index($_, '+') > 0);
# 	next if ($_ =~ /s\d+/);
# 	next if ($_ =~ /<[^>]+>/);

	chop($_);
	my ($word, @did_freqs) = split(' ', $_);

	foreach my $did_freq (@did_freqs) {
	    my ($did, $freq) = split(':', $did_freq);
	    my ($freq, $pos) = split('@', $freq);
	    
	    $doc_length{$did} += $freq;
	}
    }
    close(READER);

    $fp =~ s|[^/]*.idx(.gz)?$||; # get the dirname
    if ($opt{txt}) { # txt形式
	open(OUT, "> ${fp}doc_length.txt") or die;
	foreach my $did (keys %doc_length) {
	    printf OUT "%s %d\n", $did, $doc_length{$did};
	}
	close(OUT);
    }
    else { # Storable形式
	store(\%doc_length, "${fp}doc_length.bin") or die;
    }
}
