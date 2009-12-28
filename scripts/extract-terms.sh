#!/bin/sh


# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf

source $SHELL_RCFILE


XMLFILES=$1
OUTDIR_PREFIX=$2
ONLY_INLINKS=$3
mkdir -p $workspace_mkidx/logfiles 2> /dev/null
LOGFILE=$workspace_mkidx/logfiles/logfile.of.`basename $XMLFILES`
MKIDX_OPTIONS="-syn -infiles $XMLFILES -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z -logfile $LOGFILE -outdir_prefix $OUTDIR_PREFIX $ONLY_INLINKS"


# ログファイルが残っている場合は削除
touch $LOGFILE
rm $LOGFILE 2> /dev/null
touch $LOGFILE


# スワップしないように仕様するメモリサイズを制限する(max 2GB)
ulimit -m $mem_size_for_mkidx
ulimit -v $mem_size_for_mkidx


# ファイル単位でtermの抽出
# SYNノードを含む係り受け関係は除外、5MBを越える標準フォーマットからは抽出しない
until [ `tail -1 $LOGFILE | grep finish` ]
do
    perl -I $scriptdir $scriptdir/make_idx.pl $MKIDX_OPTIONS
done
