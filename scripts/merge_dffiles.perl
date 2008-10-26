#!/usr/bin/env perl

# $Id$

#####################################################
# 各インデックスから作成された.dfファイルをマージする
#####################################################

use strict;
use encoding 'utf8';
use Encode;
use Getopt::Long;
use FileHandle;

# binmode(STDOUT, ':encoding(euc-jp)');
binmode(STDOUT, ':encoding(utf8)');

my (%opt);
GetOptions(\%opt, 'z', 'dpnd_th=s', 'syngraph_dpnd_th=s');

$opt{n} = 0 unless ($opt{n});
$opt{th} = 0 unless ($opt{th});
$opt{syngraph_dpnd_th} = 9 unless ($opt{syngraph_dpnd_th});
$opt{dpnd_th} = 1 unless ($opt{dpnd_th});
$opt{numerical} = 1 if (!$opt{numerical} && !$opt{string});

# ファイルをオープンする
my @FH;
my $FILE_NUM = 0;
my @tmp_INDEX;
foreach my $ftmp (sort {$a cmp $b} @ARGV) {
    $FH[$FILE_NUM] = new FileHandle;
    if ($opt{z}) {
	open($FH[$FILE_NUM], "zcat $ftmp |") or die "$!\n";
    } else {
	open($FH[$FILE_NUM], $ftmp) or die "$!\n";
    }
    binmode($FH[$FILE_NUM], ':utf8');

    # 各ファイルの1行目を読み込み、ソートする前の初期@INDEX(@tmpINDEX)を作成する
    if ($_ = $FH[$FILE_NUM]->getline) {
	chop($_);
	my @fields = split(' ', $_);
	my $key = $fields[$opt{n}];
	splice(@fields, $opt{n}, 1);
	my $val = join(' ', @fields);
	push(@tmp_INDEX, {midasi => $key, data => $val, file_num => $FILE_NUM});
    }
    $FILE_NUM++;  
}

my @INDEX = sort {$a->{midasi} cmp $b->{midasi}} @tmp_INDEX;
my $buf;

# @INDEXのある限り次の行を読み込む
while (@INDEX) {
    my $index = shift(@INDEX);

    # 見出し語が同じ時はbufの後に追加
    if ($buf->{midasi} eq $index->{midasi}) {
	if ($opt{numerical}) {
	    $buf->{data} += $index->{data};
	} else {
	    $buf->{data} .= $index->{data};
	}
    }
    # 見出し語が変化した場合はbufを出力して、見出し語を変える
    else {
	if ($buf->{midasi}) {
	    if ($buf->{midasi} !~ /\?/) {
		unless ($buf->{midasi} =~ /\-\>/) {
		    print $buf->{midasi} ." " . $buf->{data} . "\n";
		} else {
		    # 係り受け
		    if ($buf->{midasi} =~ /s\d+/) {
			print $buf->{midasi} ." " . $buf->{data} . "\n" if ($buf->{data} > $opt{syngraph_dpnd_th});
		    } else {
			print $buf->{midasi} ." " . $buf->{data} . "\n" if ($buf->{data} > $opt{dpnd_th});
		    }
		}
	    }
	}
	$buf->{midasi} = $index->{midasi};
	$buf->{data} = $index->{data};
    }

    # 先ほど取り出したファイル番号について，新しい行を取り出し，@INDEXの適当な位置に挿入
    if (($_ = $FH[$index->{file_num}]->getline)) {
	chop($_);
	my @fields = split(' ', $_);
	my $key = $fields[$opt{n}];
	splice(@fields, $opt{n}, 1);
	my $val = join(' ', @fields);
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
    unless ($buf->{midasi} =~ /\-\>/) {
	print $buf->{midasi} ." " . $buf->{data} . "\n";
    } else {
	if ($buf->{midasi} =~ /s\d+/) {
	    print $buf->{midasi} ." " . $buf->{data} . "\n" if ($buf->{data} > $opt{syngraph_dpnd_th});
	} else {
	    print $buf->{midasi} ." " . $buf->{data} . "\n"
	}
    }
}

# ファイルをクローズする
for (my $f_num = 0; $f_num < $FILE_NUM; $f_num++) {
   $FH[$f_num]->close;
}
