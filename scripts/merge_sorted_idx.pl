#!/usr/bin/env perl

# $Id$

############################################################################
# ソートされたインデックスファイルをマージするプログラム(ダイナミックに出力)
############################################################################

use strict;
use utf8;
binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
use Encode;
use Getopt::Long;
use FileHandle;
use PerlIO::gzip;

my (%opt);
GetOptions(\%opt, 'dir=s', 'suffix=s', 'mapfile=s', 'z');

# データのあるディレクトリを開く
opendir (DIR, $opt{dir}) || die "$!\n";

# @INDEXは要素数を入力ファイル数とするハッシュの配列
# ハッシュの要素として、
#  ファイル番号(file_num)、
#  最後に読み込んだ行の見出し語(midasi)、
#  最後に読み込んだ行のテキスト/頻度文字列(data) 
# を持ち、常に見出し語でソートされている
# ex.  ((0 あい "1:1 3:3 4:2") (2 あい "8:2 9:1") (1 あう "5:3 7:2")) ・・・


my %sid2tid = ();
if ($opt{mapfile}) {
    open (FILE, $opt{mapfile}) or die "$!";
    while (<FILE>) {
	chop;

	my ($sid, $tid) = split (/ /, $_);
	$sid2tid{$sid} = $tid;
    }
    close (FILE);
}


# ファイルをオープンする
my @FH;
my $FILE_NUM = 0;
my @tmp_INDEX;
foreach my $ftmp (sort {$a <=> $b} readdir(DIR)) {
    # .idxファイルが対象
    if($opt{suffix}){
	next if($ftmp !~ /.+\.$opt{suffix}$/);
    }else{
	next if ($ftmp !~ /.+\.idx$/);
    }

    $FH[$FILE_NUM] = new FileHandle;
    if ($opt{z}) {
	open($FH[$FILE_NUM], '<:gzip', "$opt{dir}/$ftmp") || die "$!\n";
	binmode($FH[$FILE_NUM], ':utf8');
    } else {
	open($FH[$FILE_NUM], '<:utf8', "$opt{dir}/$ftmp") || die "$!\n";
    }

    # 各ファイルの1行目を読み込み、ソートする前の初期@INDEX(@tmpINDEX)を作成する
    while ($_ = $FH[$FILE_NUM]->getline) {
	chop;
	if ($_ =~ /^([^ ]+) (.+)/) {
	    push(@tmp_INDEX, {midasi => $1, data => $2, file_num => $FILE_NUM});
	    last;
	} else {
#	    print STDERR "Format error!!\n";
#	    print STDERR encode('utf8', $_) . "\n";
	}
    }
    $FILE_NUM++;
}

my @INDEX = sort {$a->{midasi} cmp $b->{midasi}} @tmp_INDEX;
my ($pre_midasi, @indices);

# @INDEXのある限り次の行を読み込む
while (@INDEX) {

    my $index = shift(@INDEX);

    # 見出し語が同じ時はbufの後に追加
    if ($pre_midasi && $pre_midasi eq $index->{midasi}) {
	push(@indices, split(/ /, $index->{data}));
    }
    # 見出し語が変化した場合はbufを出力して、見出し語を変える
    else {
	# 文書IDのソート
	if ($opt{mapfile}) {
	    my @buf2 = ();
	    # print STDERR encode_utf8($pre_midasi), ' ', scalar(@indices), "\n";
	    foreach my $doc (@indices) {
		my ($fid, $string) = split (/:/, $doc);
		push (@buf2, sprintf ("%s:%s", $sid2tid{$fid}, $string)) if (exists $sid2tid{$fid});
	    }
	    @indices = @buf2;
	}

	@indices = sort({$a <=> $b} @indices);

	if ($pre_midasi) {
	    print $pre_midasi, ' ', join(' ', @indices), "\n";
	}

	$pre_midasi = $index->{midasi};
	@indices = ();
	push(@indices, split(/ /, $index->{data}));
    }

    # 先ほど取り出したファイル番号について，新しい行を取り出し，@INDEXの適当な位置に挿入
    while (($_ = $FH[$index->{file_num}]->getline)) {
	chop($_);
        unless ($_ =~ /^([^ ]+) (.+)/) {
	    print STDERR "Format error!!\n";
	    print STDERR encode('utf8', $_) . "\n";
	} else {
	    $index->{midasi} = $1;
	    $index->{data} = $2;

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
	    last;
	}
    }
}

if ($opt{mapfile}) {
    my @buf2 = ();
    foreach my $doc (@indices) {
	my ($fid, $string) = split (/:/, $doc);
	push (@buf2, sprintf ("%s:%s", $sid2tid{$fid}, $string)) if (exists $sid2tid{$fid});
    }
    @indices = @buf2;
}

@indices = sort({$a <=> $b} @indices);

print $pre_midasi, ' ', join(' ', @indices), "\n" if $pre_midasi;

# ファイルをクローズする
for (my $f_num = 0; $f_num < $FILE_NUM; $f_num++) {
   $FH[$f_num]->close;
}
