#!/usr/bin/env perl

# usage: idx2df.pl 00.idx 01.idx.gz

use strict;
use utf8;
use Encode;

# binmode(STDIN, ":encoding(utf8)");
# binmode(STDOUT, ":encoding(utf8)");

foreach my $fp (@ARGV){
    if($fp =~ /^(.+)\.gz$/){
	open(READER, "zcat $fp | ") or die;
	open(WRITER, "> $1.df") or die;
    }else{
	open(READER, $fp) or die;
	open(WRITER, "> $fp.df") or die;
    }

    while(<READER>){
	chop($_);
	my($word, @docs) = split(/ /, decode('utf8', $_));
	my $size = scalar(@docs);
	$word = encode('utf8', $word);
	print WRITER "$word $size\n";
    }
    close(READER);
    close(WRITER);
}
