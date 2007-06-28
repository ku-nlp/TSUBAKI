#!/usr/bin/env perl

# $Id$

#################################################################
# idxファイルをバイナリ化するプログラム(オフセット値も同時に保存)
#################################################################

use strict;
use Binarizer;
use utf8;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'wordth=i', 'dpndth=i');

# 足切りの閾値
my $wordth = $opt{wordth} ? $opt{wordth} : 0;
my $dpndth = $opt{dpndth} ? $opt{dpndth} : 10;

&main();

sub main {
    unless ($ARGV[0] =~ /(.*?)([^\/]+)\.(idx.*)$/){
	die "file name is not *.idx\n"
    }else{
	# 引数として*.idxファイルをとる
	my $DIR = $1;
	my $NAME = $2;

	my $lcnt = 0;
	my $bins = {word => new Binarizer($wordth, "${DIR}/idx$NAME.word.dat", "${DIR}/offset$NAME.word.cdb"),
		    dpnd => new Binarizer($dpndth, "${DIR}/idx$NAME.dpnd.dat", "${DIR}/offset$NAME.dpnd.cdb")};

	open (READER, '<:utf8', "${DIR}/$NAME.idx") || die "$!\n";
	while (<READER>) {
	    print STDERR "\rnow binarizing... ($lcnt)" if(($lcnt%1113) == 0);
	    $lcnt++;

	    chomp;
	    my ($index, @dlist) = split;

	    my $bin = $bins->{word};
	    $bin = $bins->{dpnd} if(index($index, '->') > 0);

	    $bin->add($index, \@dlist);
	}
	print STDERR "\rbinarizing ($lcnt) done.\n";
	close(READER);

	$bins->{word}->close();
	$bins->{dpnd}->close();
    }
}

