#!/bin/sh

# ★文書頻度データベースを更新するスクリプト

# usage: sh update-dfdb.sh dfdbdir dftype newfile
#
# dfdbdir ... 現在のDFDBがおいてあるディレクトリ
# dftype  ... DFDBの種類（word or dpnd）
# newfile ... 新たに追加したいDFデータ



# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf



# 引数の代入
dfdbdir=$1
dftype=$2
newfile=$3

# cdbファイルの内容をテキストに変換
for cdbf in `ls $dfdbdir/*.$dftype.*`
do
    echo perl $scriptdir/cdb2txt.perl $cdbf
    perl $scriptdir/cdb2txt.perl $cdbf
done

# 既存のデータと新データをマージ
echo perl $utildir/../scripts/merge_files.perl -n 0 $dfdbdir/*.$dftype.txt* $newfile > df.$dftype.tmp.$$
perl $utildir/../scripts/merge_files.perl -n 0 $dfdbdir/*.$dftype.txt* $newfile > df.$dftype.tmp.$$

# テキストデータをCDB化
echo perl -I $utildir $scriptdir/make-df-db.perl < df.$dftype.tmp.$$
perl -I $utildir $scriptdir/make-df-db.perl < df.$dftype.tmp.$$

# 後処理
rm $dfdbdir/*.txt*
rm df.$dftype.tmp.$$

