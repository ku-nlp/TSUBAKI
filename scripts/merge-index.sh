#!/bin/sh

# 1万件ごとのインデックスデータを100万件単位にマージするスクリプト

# ★以下の値を変更すること
workspace=/tmp/mg_tsubaki_idx
scriptdir=$HOME/cvs/SearchEngine/scripts



id=$1
flist=$2
mkdir $workspace 2> /dev/null
cd $workspace

mkdir $id 2> /dev/null
cd $id

# インデックスデータをコピー
for f in `egrep "i$id...idx.gz" $flist`
do
    echo scp $f ./
    scp $f ./
done
cd ..

# ディスク上でマージ
echo "perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz"
perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz
rm -r $id



fname=$id.idx.gz

# バイナリ化
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname
perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname

# 文書頻度の取得
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# 文書長データベースの作成
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
