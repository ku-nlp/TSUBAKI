#!/usr/bin/env perl

# $Id$

#################################################################
# idxファイルをバイナリ化するプログラム(オフセット値も同時に保存)
#################################################################

use strict;
use Binarizer;
use utf8;
use Getopt::Long;
use Encode;

my (%opt);
GetOptions(\%opt, 'wordth=i', 'dpndth=i', 'position', 'verbose', 'z');

# 足切りの閾値
my $wordth = $opt{wordth} ? $opt{wordth} : 0;
my $dpndth = $opt{dpndth} ? $opt{dpndth} : 0;

&main();

sub main {
    my $fp = $ARGV[0];
    unless ($fp =~ /(.*?)([^\/]+)\.(idx.*)$/) {
	die "file name is not *.idx\n"
    } else {
	# 引数として*.idxファイルをとる
	my $DIR = $1;
	$DIR = '.' unless $DIR; # カレントディレクトリにあるファイルの場合、$DIRが空になるので、'.'を入れる
	my $NAME = $2;

	my $lcnt = 0;
	my $bins = {
	    word => new Binarizer($wordth, "${DIR}/idx$NAME.word.dat", "${DIR}/offset$NAME.word.cdb", $opt{position}, $opt{verbose}),
	    dpnd => new Binarizer($dpndth, "${DIR}/idx$NAME.dpnd.dat", "${DIR}/offset$NAME.dpnd.cdb", $opt{position}, $opt{verbose})
	};

	if ($opt{z}) {
	    open (READER, "zcat $fp |") || die "$!\n";
	} else {
	    open (READER, $fp) || die "$!\n";
	}

	while (<READER>) {
	    print STDERR "\rnow binarizing... ($lcnt)" if (($lcnt%1000) == 0);
	    $lcnt++;

	    chomp;
	    my ($index, @dlist) = split(' ', decode('utf8', $_));

	    my $bin = $bins->{word};
	    $bin = $bins->{dpnd} if (index($index, '->') > 0);

	    $bin->add($index, \@dlist);
	}
	print STDERR "\rbinarizing ($lcnt) done.\n";
	close(READER);

	$bins->{word}->close();
	$bins->{dpnd}->close();
    }
}

