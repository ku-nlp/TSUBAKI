#!/usr/bin/env perl

# make urllist or url2sid

# Usage: $0 /fir/kawahara/ocw/data.1301/html

use strict;
use File::Find;

our $TOP_DIR = $ARGV[0] ? $ARGV[0] : '.';

File::Find::find({wanted => \&wanted}, $TOP_DIR);


sub wanted {
    my $basename = $_;
    if ($basename =~ /^.*\.html\z/s) {
	my $sid = $basename;
	$sid =~ s/\.html$//;

	open(F, $File::Find::name) or die "Cannot open \"$File::Find::name\"\n";
	my $line = <F>;
	if ($line =~ /^HTML (.+)/) {
	    my $url = $1;
	    $url =~ s/\s+$//;
	    print "$url $sid\n";
	}
	else {
	    die "Invalid line:$line";
	}
    }
}
