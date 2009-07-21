#!/bin/sh

# 1万件ごとのインデックスデータを100万件単位にマージするスクリプト

# usage: sh merge-index.sh [-syn] 000 /somewhere/flist


# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mgidx

source $SHELL_RCFILE


# スワップしないように仕様するメモリサイズを制限する(max 4GB)
ulimit -m 4194304
ulimit -v 4194304


# SYNGRAPH検索用インデックスかどうかのチェック
type=
if [ $1 = "-syn" ];
then
    type="-syn"
    shift
fi
id=$1
flist=$2

# 作業ディレクトリの作成
mkdir -p $workspace 2> /dev/null
cd $workspace

mkdir $id 2> /dev/null
cd $id


# インデックスデータをコピー
for f in `egrep "i$id.*idx.gz" $flist`
do
    echo scp $f ./
    scp -o "BatchMode yes" -o "StrictHostKeyChecking no" $f ./
done
cd ..


# ディスク上でマージ
echo "perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz"
perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz
rm -r $id


fname=$id.idx.gz

# バイナリ化
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname $type
perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname $type

# 文書頻度の取得
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# 文書長データベースの作成
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
