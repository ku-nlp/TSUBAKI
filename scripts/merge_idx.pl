#!/usr/bin/env perl

# $Id$

###################################################
# 単語頻度の計数結果をマージ (全てをメモリ上に保持)
###################################################

use strict;
use utf8;
use Getopt::Long;
use Encode;

my (%opt); GetOptions(\%opt, 'dir=s', 'suffix=s', 'n=s');

# 単語IDの初期化
my %freq;
my $fcnt = 0;

$opt{suffix} = 'idx' unless $opt{suffix};

# ディレクトリが指定された場合
if ($opt{dir}) {

    # データのあるディレクトリを開く
    opendir (DIR, $opt{dir}) or die;

    foreach my $file (sort {$a <=> $b} readdir(DIR)) {
	# 拡張子が$opt{suffix}(デフォルトidx)であるファイルが対象
	next if($file !~ /.+\.$opt{suffix}$/);

	print STDERR "\r($fcnt)" if($fcnt%113 == 0);
	$fcnt++;

	# ファイルから読み込む
	open (FILE, '<:utf8', "$opt{dir}/$file") or die("no such file $file\n");
	while (<FILE>) {
	    &ReadData($_);
	}
	close FILE;

	if (defined($opt{n})) {
	    if ($fcnt % $opt{n} == 0) {
		my $fname = sprintf("$opt{dir}.%d.%d.%s", $fcnt/$opt{n}, $$, $opt{suffix});
		open(WRITER, "> $fname") or die;
		foreach my $k (sort {$a cmp $b} keys %freq) {
		    my $k_utf8 = encode('utf8', $k);
		    print WRITER "$k_utf8 $freq{$k}\n";
		}
		close(WRITER);
		%freq = ();
	    }
	}
    }
    closedir(DIR);
}

# ディレクトリの指定がない場合は標準入力から読む
else {
    while (<STDIN>) {
	&ReadData($_);
    }
}

print STDERR "\r($fcnt) done.\n";

if (defined($opt{n})) {
    my $size = scalar(keys %freq);
    if ($size > 0) {
	my $fname = sprintf("$opt{dir}.%d.%d.%s", 1 + $fcnt/$opt{n}, $$, $opt{suffix});
	open(WRITER, "> $fname") or die;
	foreach my $k (sort {$a cmp $b} keys %freq) {
	    my $k_utf8 = encode('utf8', $k);
	    print WRITER "$k_utf8 $freq{$k}\n";
	}
	close(WRITER);
    }
}else{
    # 標準出力に出力
    foreach my $wid (sort {$a cmp $b} keys %freq) {
	my $w_utf8 = encode('utf8', $wid);
	print "$w_utf8 $freq{$wid}\n";
    }
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
