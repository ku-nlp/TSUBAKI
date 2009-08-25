#!/usr/bin/env perl

# $Id$

# 標準フォーマットを管理しているホストを調べる

use strict;
use utf8;
use SidRange;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'flist=s');

&main();

sub main {
    my $range = new SidRange();

    if ($opt{flist}) {
	open (READER, $opt{flist}) or die "$!";
	while (<READER>) {
	    chop;
	    my $file = $_;

	    my ($dir, $name) = ($file =~ /(.+?)\/([^\/]+)$/);
	    my ($did) = ($name =~ /^(\d+)/);

	    my $host = $range->lookup($did);
	    print $file . " " . $host . "\n";
	}
	close (READER);
    } else {
	foreach my $did (@ARGV) {
	    my $host = $range->lookup($did);
	    print $did . " " . $host . "\n";
	}
    }
}
