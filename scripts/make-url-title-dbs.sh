#!/bin/sh

# URL、タイトルデータベースを作成するスクリプト

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf


indir=$1
ofile=$indir.url.title

rm $ofile 2> /dev/null

# $indirは10000件分の標準フォーマットが収められたディレクトリがあるディレクトリ
for d in `ls $indir`
do
    # $dは10000件分の標準フォーマットが収められたディレクトリ
    echo "perl $scriptdir/extract-url-title.perl -z -url -title -dir $indir/$d >> $ofile"
    perl $scriptdir/extract-url-title.perl -z -url -title -dir $indir/$d >> $ofile
done

echo perl $scriptdir/make-url-title-cdbs.perl $ofile
perl $scriptdir/make-url-title-cdbs.perl $ofile

mv $ofile.title.cdb $indir.title.cdb
mv $ofile.url.cdb $indir.url.cdb
