#!/usr/bin/env perl

# $id:$

# cdbの内容をテキストに書き出す

# キーと値のペア（キーを文字列順にソート）

use strict;
use CDB_File;
use utf8;
use Encode;
use FileHandle;

my $N = 10000000;

foreach my $cdbfp (@ARGV) {
    tie my %cdb, 'CDB_File', $cdbfp or die "$0: can't tie to $cdbfp $!\n";

    my %buf;
    my $cnt = 0;
    my $filecnt = 0;
    while (my ($k, $v) = (each %cdb)) {
	$buf{$k} = $v;
	print STDERR "\r$cnt" unless (++$cnt%100000);
	if ($cnt % $N == 0) {
	    &output_tmpfile(\%buf, $cdbfp, $filecnt++);
	    %buf = ();
	}
    }
    if (defined %buf) {
	&output_tmpfile(\%buf, $cdbfp, $filecnt++);
    }
    untie %cdb;

    my $txtfp = $cdbfp;
    $txtfp =~ s/cdb/txt/;
    print $txtfp . "\n";
    if ($filecnt == 1) {
	`mv $cdbfp.0.txt $txtfp`;
    } else {
	my @FH;
	my $FILE_NUM = 0;
	my @tmp_INDEX;
	for (my $i = 0; $i < $filecnt; $i++) {
	    my $ftmp = "$cdbfp.$i.txt";
	    $FH[$FILE_NUM] = new FileHandle;
	    open($FH[$FILE_NUM], '<:utf8', $ftmp) or die "$!\n";

	    # 各ファイルの1行目を読み込み、ソートする前の初期@INDEX(@tmpINDEX)を作成する
	    if ($_ = $FH[$FILE_NUM]->getline) {
		chop($_);
		my ($key, $val) = split(/ /, $_);
		push(@tmp_INDEX, {midasi => $key, data => $val, file_num => $FILE_NUM});
	    }
	    $FILE_NUM++;  
	}

	my @INDEX = sort {$a->{midasi} cmp $b->{midasi}} @tmp_INDEX;
	my $buf;

	open(WRITER, '>:utf8', $txtfp);
	# @INDEXのある限り次の行を読み込む
	while (@INDEX) {
	    my $index = shift(@INDEX);

	    # 見出し語が同じ時はbufの後に追加
	    if ($buf->{midasi} eq $index->{midasi}) {
		$buf->{data} += $index->{data};
	    }
	    # 見出し語が変化した場合はbufを出力して、見出し語を変える
	    else {
		if ($buf->{midasi}) {
		    print WRITER $buf->{midasi} ." " . $buf->{data} . "\n";
		}
		$buf->{midasi} = $index->{midasi};
		$buf->{data} = $index->{data};
	    }

	    # 先ほど取り出したファイル番号について，新しい行を取り出し，@INDEXの適当な位置に挿入
	    if (($_ = $FH[$index->{file_num}]->getline)) {
		chop($_);
		my ($key, $val) = split(/ /, $_);
		$index->{midasi} = $key;
		$index->{data} = $val;
	    
		my $i;
		for ($i = $#INDEX; $i >= 0; $i--) {
		    if (($index->{midasi} cmp $INDEX[$i]{midasi}) >= 0) {
			splice(@INDEX, $i + 1, 0, $index);
			last;
		    }
		}
		if ($i == -1) {
		    splice(@INDEX, 0, 0, $index);
		}
	    }
	}

	if ($buf->{midasi}) {
	    print WRITER $buf->{midasi} ." " . $buf->{data} . "\n";
	}
	close(WRITER);

	# ファイルをクローズする
	for (my $f_num = 0; $f_num < $FILE_NUM; $f_num++) {
	    $FH[$f_num]->close;
	}

	# tmpファイルの削除
	for (my $i = 0; $i < $filecnt; $i++) {
	    my $ftmp = "$cdbfp.$i.txt";
	    `rm $ftmp`;
	}
    }
}

sub output_tmpfile {
    my ($buf, $cdbfp, $fcnt) = @_;

    open(WRITER, "> $cdbfp.$fcnt.txt");
    foreach my $k (sort {$a cmp $b} keys %$buf) {
	my $v = $buf->{$k};
	print WRITER "$k $v\n";
    }
    close(WRITER);
}
