#!/bin/sh

# 1万ページ毎にtgzされた標準フォーマットの塊からインデックスを抽出するスクリプト

# usage: sh make-index.sh [-knp|-syn|-english] [-inlinks] iccc100:/data2/skeiji/embed_knp_and_syngraph_080512/s01573.tgz

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mkidx

source $SHELL_RCFILE

SLEEPTIME=`expr $RANDOM % 600`
# sleep $SLEEPTIME

# 作成するインデックスのタイプ(-knp/-syn/-english)
type=$1

scheme=
block_type=-use_block_type

# -englishのときは、schemeをCoNLLにし、ブロックタイプはさしあたり使わない
if [ $type = "-english" ]; then
    scheme="-scheme CoNLL"
    block_type=
fi

# インリンクインデックスの作成かどうかのチェック
inlinks=
if [ $2 = "-inlinks" ];
then
    inlinks=$2
    shift
fi

# 論文検索かどうかのチェック
IPSJ=
if [ $2 = "-ipsj" ];
then
    IPSJ=$2
    shift
fi


fp=$2
id=`basename $fp | cut -f 2 -d 's' | cut -f 1 -d '.'`

xdir=s$id
idir=i$id

mkdir -p $workspace 2> /dev/null
cd $workspace

scp -o "BatchMode yes" -o "StrictHostKeyChecking no" -r $fp ./

mkdir -p $idir 2> /dev/null

echo tar xzf $xdir.tgz
tar xzf $xdir.tgz
rm -f $xdir.tgz

# スワップしないように仕様するメモリサイズを制限する(max 4GB)
ulimit -m 4097152
ulimit -v 4097152


LOGFILE=$workspace/$xdir.log
touch $LOGFILE

# ファイル単位でインデックスの抽出
# SYNノードを含む係り受け関係は除外、5MBを越える標準フォーマットからは抽出しない
command="perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z $inlinks -logfile $LOGFILE $IPSJ $scheme $block_type"
echo $command
until [ `tail -1 $LOGFILE | grep finish` ] ;
do
    $command
done
rm -fr $xdir


# 1万ページ分のインデックスをマージ

# N件ずつメモリを使ってマージ
N=50
echo perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
rm -fr $idir

# ディスク上でマージ
tmpdir=$idir"_tmp"
mkdir -p $tmpdir 2> /dev/null
mv $idir.*.*gz $tmpdir

echo perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
rm -fr $tmpdir

mkdir $workspace/finish 2> /dev/null
mv $idir.idx.gz finish/
