#!/usr/bin/env perl

# $Id$

# インデックスのフォーマットを変更するスクリプト

# Usage:
# perl conv.perl -idxfile idx000.word.dat -offset offset000.word.cdb

use strict;
use utf8;
use Encode;
use Getopt::Long;
use CDB_File;

# binmode (STDERR ,":encoding(euc-jp)");

my (%opt);
GetOptions(\%opt, 'offset=s', 'idxfile=s');

&main();

sub main {


    open (my $idxfile, $opt{idxfile}) or die $!;

    open (my $new_idxfile, "> $opt{idxfile}.conv") or die $!;
    open (my $new_offfile, "> $opt{offset}") or die $!;
    my $new_offset = 0;
    foreach my $offsetf (@ARGV) {
	next unless -f $offsetf;
	tie my %offsetdb, 'CDB_File', $offsetf or die $!;
	# my $new_offsetdb = new CDB_File ("$opt{offset}.conv", "$opt{offset}.conv.tmp") or die $!;
	while (my ($term, $offset) = each %offsetdb) {
	    my $byte_data = &convert($idxfile, $offset);
	    print $new_idxfile $byte_data;
	    print $new_offfile "$term  $new_offset\n" ;
	    # $new_offsetdb->insert($term, $new_offset);
	    $new_offset += length($byte_data);

	    # last if ($new_offset > 10000);
	}
	untie %offsetdb;
    }
    close ($new_idxfile);
    # $new_offsetdb->finish(); 
    close ($new_offfile);
}


sub convert {
    my ($idxfile, $offset) = @_;

    my $data;
    seek($idxfile, $offset, 0);

    my $buf;
    while (read($idxfile, $buf, 1)) {
	last if (unpack('c', $buf) == 0);
    }

    # termの文書頻度（100万文書中）
    read($idxfile, $buf, 4);
    my $ldf = unpack('L', $buf);
    $data .= $buf;

    # 文書IDの読み込み
    read($idxfile, $buf, 4 * $ldf);
    $data .= $buf;

    # 場所情報フィールドのバイト長を取得
    read($idxfile, $buf, 4);
    my $poss_size = unpack('L', $buf);

    # スコア情報フィールドのバイト長を取得
    read($idxfile, $buf, 4);
    my $scores_size = unpack('L', $buf);

    # 場所情報をインデックスデータから読み込む
    my $posdata;
    read($idxfile, $posdata, $poss_size);

    # スコア情報をインデックスデータから読み込む
    my $scrdata;
    read($idxfile, $scrdata, $scores_size);

    my $_offset_of_scr = 0;
    foreach my $_i (1..$ldf) {
	my $size = unpack ('L', substr ($scrdata, $_offset_of_scr, 4));
	my $score = 0;
	foreach my $s (unpack ('S*', substr ($scrdata, $_offset_of_scr + 4, $size * 2))) {
	    $score += $s;
	}
	$data .= pack ('L', $score);
	$_offset_of_scr += (4 + $size * 2);
    }

    my $_offset_of_pos = 0;
    my $offs_of_pos_and_score = 0;
    my $data_of_pos_and_score;
    foreach my $_i (1..$ldf) {
	my $num_of_pos = unpack('L', substr ($posdata, $_offset_of_pos, 4));
	my $psize = $num_of_pos * 4 + 4;
#	my $ssize = $num_of_pos * 2;
	my $_data = substr ($posdata, $_offset_of_pos, $psize);
#	$_data .= substr ($scrdata, $_offset_of_scr + 4, $ssize);

	$data_of_pos_and_score .= $_data;
	$data .= pack('L', $offs_of_pos_and_score);

	$offs_of_pos_and_score += length($_data);
	$_offset_of_pos += $psize;
#	$_offset_of_scr += ($ssize + 4);
    }
    $data .= $data_of_pos_and_score;
    my $size = pack('L', length($data));
    $data = $size . $data;

    return $data;
}

sub check {
    my $offset = 4518267282;
    my $offset = 23964514674;
    my $offset = 20125860904;

    open (F, "/work/skeiji/idx.version4/001/idx.version3/idx000.word.dat.conv") or die $!;
    seek(F, $offset, 0);

    my $buf;
    read(F, $buf, 4);
    my $total_size = unpack('L', $buf);

    read(F, $buf, $total_size);

    my $ldf = unpack('L', substr($buf, 0, 4));

    my @dat = unpack("L*", substr($buf, 4, $ldf * 8));

    my $_offset = 4 + $ldf * 8;
    foreach my $_i (0..$ldf - 1) {
	my $_size = unpack('L', substr($buf, $_offset + $dat[$ldf + $_i], 4));
	printf ("%d %d %d %d %s %s\n",
		$_i,
		$dat[$_i],
		$dat[$ldf + $_i],
		$_size,
		join (",", unpack("L$_size", substr($buf, $_offset + $dat[$ldf + $_i] + 4, $_size * 4))),
		join (",", unpack("S$_size", substr($buf, $_offset + $dat[$ldf + $_i] + 4 + $_size * 4, $_size * 2)))
	    );
    }
    close (F);
}

