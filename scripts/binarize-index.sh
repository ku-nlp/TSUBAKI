#!/bin/sh

# インデックスデータをバイナリ化し、各種データベースを作成するスクリプト

# ★以下の変数の値を変えること
workspace=/tmp/bin_tsubaki
scriptdir=$HOME/cvs/SearchEngine/scripts

# SYNGRAPHインデックスかどうかの判定
if [ $1 = "-syn" ];
then
    type=$1
    shift
fi

fp=$1
fname=`basename $fp`
id=`echo $fname | cut -f 1 -d '.'`

mkdir $workspace 2> /dev/null
cd $workspace

scp $fp ./

# バイナリ化
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z $type -quiet $fname
perl -I $scriptdir $scriptdir/binarize_idx.pl -z $type -quiet $fname

# 文書頻度の取得
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# 文書長データベースの作成
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
