#!/usr/bin/env perl

# $Id$

###################################################
# 単語頻度の計数結果をマージ (全てをメモリ上に保持)
###################################################

use strict;
use encoding 'utf8';
use Getopt::Long;
my (%opt); GetOptions(\%opt, 'dir=s');

# 単語IDの初期化
my %freq;

# ディレクトリが指定された場合
if ($opt{dir}) {

    # データのあるディレクトリを開く
    opendir (DIR, $opt{dir});

    foreach my $ftmp (sort {$a <=> $b} readdir(DIR)) {
	# .idxファイルが対象
	next if ($ftmp !~ /.+\.idx$/);

	# ファイルから読み込む
	open (FILE, '<:utf8', "$opt{dir}/$ftmp") || die("no such file $ftmp\n");
	while (<FILE>) {
	    &ReadData($_);
	}
	close FILE;
    }

    closedir(DIR);
}

# ディレクトリの指定がない場合は標準入力から読む
else {
    while (<STDIN>) {
	&ReadData($_);
    }
}

# 標準出力に出力
foreach my $wid (sort keys %freq) {
    print "$wid $freq{$wid}\n";
}

# データを読んで、各単語が出現するDocumentIDをマージ
sub ReadData
{
    my ($input) = @_;
    chomp $input;

    my ($str, $did) = split(/\s+/, $input);
    
    # 各単語IDの頻度を計数
    if (defined $freq{$str}) {
	$freq{$str} .= " $did";
    } else {
	$freq{$str} = $did;
    }
}
