#!/bin/sh

# $Id$

# 文書頻度データベースを作成するスクリプト


# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mkdfdb
mkdir -p $workspace 2> /dev/null
cd $workspace


opt=
while getopts z OPT
do
    case $OPT in
	z)  opt=" -z"
	    ;;
    esac
done
shift `expr $OPTIND - 1`



echo merging DF files...
perl $scriptdir/merge_dffiles.perl $opt $@ > $workspace/merged.dffiles
echo done.


echo making DF database...
perl -I $utildir $scriptdir/make-df-db.perl < $workspace/merged.dffiles
rm $workspace/merged.dffiles
echo done.
