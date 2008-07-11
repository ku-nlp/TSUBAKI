#!/bin/sh

# 1万ページ毎にtgzされた標準フォーマットの塊からインデックスを抽出するスクリプト

# usage: sh make-index.sh [-knp|-syn] iccc100:/data2/skeiji/embed_knp_and_syngraph_080512/s01573.tgz

# ★以下の値を変更すること
workspace=/data2/skeiji/smallset/mkidx
scriptdir=$HOME/work/new-syngraph-test/mkidx/SearchEngine/scripts


# 作成するインデックスのタイプ(-knp/-syn)
type=$1
fp=$2
id=`basename $fp | cut -f 2 -d 's' | cut -f 1 -d '.'`

xdir=s$id
idir=i$id

mkdir $workspace 2> /dev/null
cd $workspace

scp -r $fp ./

mkdir $idir 2> /dev/null

echo tar xzf $xdir.tgz
tar xzf $xdir.tgz
rm $xdir.tgz

# スワップしないように仕様するメモリサイズを制限する(max 2GB)
ulimit -m 2097152
ulimit -v 2097152

# ファイル単位でインデックスの抽出
# SYNノードを含む係り受け関係は除外、5MBを越える標準フォーマットからは抽出しない
echo perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z
perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z
rm -r $xdir


# 1万ページ分のインデックスをマージ

# N件ずつメモリを使ってマージ
N=10
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
