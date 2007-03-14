#!/usr/bin/env perl

# $Id$

#################################################################
# idxファイルをバイナリ化するプログラム(オフセット値も同時に保存)
#################################################################

use strict;
use Binarizer;

&main();

sub main {
    unless ($ARGV[0] =~ /(.*?)([^\/]+)\.idx3$/){
	die "file name is not *.idx\n"
    }else{
	# 引数として*.idxファイルをとる
	my $DIR = $1;
	my $NAME = $2;

	my $lcnt = 0;
	my $bins = {ngram => new Binarizer( 0, "${DIR}/idx$NAME.3grm.dat", "${DIR}/offset$NAME.3grm.cdb")};

	open (READER, '<:utf8', "${DIR}/$NAME.idx3") || die "$!\n";
	while (<READER>) {
	    print STDERR "\rnow binarizing... ($lcnt)" if(($lcnt%1113) == 0);
	    $lcnt++;

	    chomp;
	    my ($index, @dlist) = split;

	    my $bin = $bins->{ngram};
	    $bin->add($index, \@dlist);
	}
	print STDERR "\rbinarizing ($lcnt) done.\n";
	close(READER);

	$bins->{ngram}->close();
    }
}
