#!/bin/sh

# 1万ページ毎にtgzされた標準フォーマットの塊からインデックスを抽出するスクリプト

# ★以下の値を変更すること
workspace=/tmp/mk_tsubaki_idx
scriptdir=$HOME/cvs/SearchEngine/scripts



fp=$1
id=`basename $fp | cut -f 2 -d 'x' | cut -f 1 -d '.'`

xdir=x$id
idir=i$id

mkdir $workspace 2> /dev/null
cd $workspace

scp -r $fp ./

mkdir $idir 2> /dev/null

echo tar xzf x$id.tgz
tar xzf x$id.tgz
rm x$id.tgz

# ファイル単位でインデックスの抽出
echo perl -I $scriptdir $scriptdir/make_idx.pl -knp -in $xdir -out $idir -position -z -compress
perl -I $scriptdir $scriptdir/make_idx.pl -knp -in $xdir -out $idir -position -z -compress
rm -r $xdir

# 1万ページ分のインデックスをマージ

# N件ずつメモリを使ってマージ
N=50
echo perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
rm -r $idir

# ディスク上でマージ
tmpdir=$idir"_tmp"
mkdir $tmpdir 2> /dev/null
mv $idir.*.*gz $tmpdir

echo perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
rm -r $tmpdir
