#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Getopt::Long;
use CDB_Reader;
use CDB_Writer;
use Encode;

my (%opt);
GetOptions(\%opt, 'idxdat=s', 'termdb=s', 'type=s', 'anchor');

my ($id) = ($opt{idxdat} =~ /idx(\d+).+?$/);

# binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# keymapfileの読み込み
my $termdb = new CDB_Reader($opt{termdb}, \%opt);
# インデックスデータをロード
open (IDXDAT, $opt{idxdat}) or die "$! $opt{idxdat}";

# 出力先
# インデックスデータ
my $outdatf = ($opt{anchor}) ? sprintf ("idxa%03d.%s.dat.2", $id, $opt{type}) : sprintf ("idx%03d.%s.dat.2", $id, $opt{type});
open (OUTDAT, "> $outdatf") or die "$!";
# オフセット
my $offset = new CDB_Writer(
    (($opt{anchor}) ? sprintf ("offseta%03d.%s.cdb.2", $id, $opt{type}) : sprintf ("offset%03d.%s.cdb.2", $id, $opt{type})),
    (($opt{anchor}) ? sprintf ("offseta%03d.%s.cdb.keymap.2", $id, $opt{type}) : sprintf ("offset%03d.%s.cdb.keymap.2", $id, $opt{type})),
    ($opt{type} eq 'word') ? 3.5 * (1024**3) : 2.5 * (1024**3)
    );

my $buf;
my $byte = 0;
my $term;
my $data;
while (read(IDXDAT, $buf, 1)) {
    if (unpack('c', $buf) != 0) {
	$term .= $buf;
	$data .= $buf;
    } else {
	# デリミタ0の分
	$data .= $buf;

	# termの文書頻度（100万文書中）
	read(IDXDAT, $buf, 4);
	$data .= $buf;
	my $ldf = unpack('L', $buf);

	# 文書IDの読み込み
	read (IDXDAT, $buf, 4 * $ldf);
	$data .= $buf;

	# 場所情報フィールドのバイト長を取得
	read(IDXDAT, $buf, 4);
	$data .= $buf;
	my $poss_size = unpack('L', $buf);

	# スコア情報フィールドのバイト長を取得
	read(IDXDAT, $buf, 4);
	$data .= $buf;
	my $scores_size = unpack('L', $buf);

	# 場所情報をインデックスデータから読み込む
	read (IDXDAT, $buf, $poss_size + $scores_size);
	$data .= $buf;

	$term = decode ('utf8', $term);
	if ($termdb->get($term)) {
	    print OUTDAT $data;
	    $offset->add($term, $byte);
	    $byte += length($data);
	}

	$data = "";
	$term = "";
    }
}
close (IDXDAT);
close (OUTDAT);
$offset->close();
