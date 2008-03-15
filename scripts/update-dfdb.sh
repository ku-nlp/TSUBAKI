#!/bin/sh

# ★文書頻度データベースを更新するスクリプト

# usage:
# sh update-dfdb.sh dfdbdir dftype newfile
#
# dfdbdir ... 現在のDFDBがおいてあるディレクトリ
# dftype  ... DFDBの種類（word or dpnd）
# newfile ... 新たに追加したいDFデータ



# ★以下のスクリプトのディレクトリを要変更
toolhome=$HOME/cvs/SearchEngine/scripts



# 引数の代入
dfdbdir=$1
dftype=$2
newfile=$3

# cdbファイルの内容をテキストに変換
for cdbf in `ls $dfdbdir/*.$dftype.*`
do
    echo perl $toolhome/cdb2txt.perl $cdbf
    perl $toolhome/cdb2txt.perl $cdbf
done

# 既存のデータと新データをマージ
echo perl $toolhome/merge_files.perl -n 0 $dfdbdir/*.$dftype.*.txt $newfile > df.$dftype.tmp.$$
perl $toolhome/merge_files.perl -n 0 $dfdbdir/*.$dftype.*.txt $newfile > df.$dftype.tmp.$$

# テキストデータをCDB化
echo perl $toolhome/make-df-db.perl < df.$dftype.tmp.$$
perl $toolhome/make-df-db.perl < df.$dftype.tmp.$$

# 後処理
rm $dfdbdir/*.txt
rm df.$dftype.tmp.$$

