#!/usr/bin/env perl

# $Id$

use strict;
use utf8;

my $tid = 0;
my %sid2tid;
foreach my $file (@ARGV) {
    if ($file =~ /\.gz$/) {
	open (F, "zcat $file |") or die $!;
    }
    else {
	open (F, $file) or die $!;
    }
    binmode (F, ':utf8');

    while (<F>) {
	chop;

	my ($midashi, @docs) = split(/\s+/, $_);
	foreach my $doc (@docs) {
	    my ($sid, $etc) = split(':', $doc);

	    next unless ($sid =~ /^[\d|\-]+$/);

	    unless (exists $sid2tid{$sid}) {
		$sid2tid{$sid} = $tid++;
	    }
	}
    }
    close (F);
}

foreach my $sid (sort {$sid2tid{$a} <=> $sid2tid{$b}} keys %sid2tid) {
    printf ("%s %06d\n", $sid, $sid2tid{$sid});
}
