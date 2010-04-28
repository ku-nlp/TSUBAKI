#!/usr/bin/env perl

# $Id$

# usage: idx2df.pl 00.idx 01.idx.gz

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Encode;

my (%opt);
GetOptions(\%opt, 'remove_tag', 'debug');

foreach my $fp (@ARGV){
    my $outf = $fp;
    if ($fp =~ /^(.+)\.gz$/) {
	$outf = $1;
	open (READER, "zcat $fp | ") or die $!;
    } else {
	open (READER, $fp) or die $!;
    }

    if ($opt{debug}) {
	open (WRITER, ">&STDOUT");
    } else {
	open (WRITER, "> $outf.df") or die $!;
    }

    binmode (READER, ':utf8');
    binmode (WRITER, ':utf8');

    my %buff = ();
    my $prev = undef;
    while(<READER>){
	chop;

	my ($term, @docs) = split(/ /, $_);
	if ($opt{remove_tag}) {
	    my ($tag, $_term) = ($term =~ /^(.*?):(.+)$/);
	    if (defined $prev && $prev ne $_term) {
		my $size = scalar(keys %buff);
		print WRITER "$prev $size\n";
		%buff = ();
	    }
	    $prev = $_term;

	    foreach my $doc (@docs) {
		my ($did, $dat) = split (/:/, $doc);
		$buff{$did} = 1;
	    }
	}
	else {
	    my $size = scalar (@docs);
	    print WRITER "$term $size\n";
	}
    }

    if ($opt{remove_tag}) {
	my $size = scalar(keys %buff);
	print WRITER "$prev $size\n";
    }


    close(READER);
    close(WRITER);
}
