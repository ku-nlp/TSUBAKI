#!/usr/bin/env perl

# $Id$

###############################################################################
# 標準入力から入力された単語を含む文書IDをindex<NAME>.datから検索するプログラム
###############################################################################

use Retrieve;
use strict;
use encoding 'utf8';
use Getopt::Long;

# idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
my %opt;
GetOptions(\%opt, 'dir=s');

my $retrieve = new Retrieve($opt{dir});

while (<STDIN>) {
    chomp;
    my @result = $retrieve->search($_);
    if (@result == 0) {
	print "No file was found.\n";
    }
    else {
	foreach my $i (@result) {
	    print "$i->{did} $i->{freq}\n";
	}
	# print "@result\n";
    }
}
