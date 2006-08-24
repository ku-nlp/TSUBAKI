#!/usr/bin/env perl

# $Id$

#################################################################
# idxファイルをバイナリ化するプログラム(オフセット値も同時に保存)
#################################################################

use strict;
use BerkeleyDB;
use Encode;

# 引数として*.idxファイルをとる
die "file name is not *.idx\n" if ($ARGV[0] !~ /(.*?)([^\/]+)\.idx$/);
my $DIR = $1;
my $NAME = $2;

# INDEXを保存するDB
my $table =  tie my %OFFSET, 'BerkeleyDB::Hash', -Filename => "${DIR}offset$NAME.db", -Flags => DB_CREATE | DB_TRUNCATE, -Cachesize => 100000000 or die "$!\n";
&EncodeDB($table);

my $offset = 0;
open (FILE, '<:utf8', "${DIR}$NAME.idx") || die "$!\n";
open (OUT, "> ${DIR}idx$NAME.dat") || die "$!\n";

while (<FILE>) {
    chomp;
    my ($word, @dlist) = split;
    my $encword = encode('utf8', $word);
    # UTFエンコードされた単語を出力
    print OUT $encword;
    # 0を出力
    print OUT pack('c', 0);
    # 文書数をlong型で出力
    print OUT pack('L', scalar(@dlist));

    for (my $i = 0; $i < @dlist; $i++) {
	my ($did, $freq) = split (/:/, $dlist[$i]);
	
	# 単語IDと頻度をLONGで出力
	print OUT pack('L', $did);
	print OUT pack('L', $freq);
    }

    # オフセットを保存し、書き込んだバイト数分増やす
    $OFFSET{$word} = $offset;
    $offset += length($encword) + 5 + 8 * @dlist;
}
close FILE;
close OUT;

# データベースのエンコード設定
sub EncodeDB{
    my ($db) = @_;
    $db->filter_fetch_key(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_key(sub {$_ = &encode('euc-jp', $_)});
    $db->filter_fetch_value(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_value(sub {$_ = &encode('euc-jp', $_)});
}
