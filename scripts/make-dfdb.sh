#!/bin/sh

# $Id$

# 文書頻度データベースを作成するスクリプト


# ★実行環境に合わせて以下の変数を変更してください
workspace=.
scriptdir=$HOME/cvs/SearchEngine/scripts
utildir=$HOME/cvs/Utils/perl



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
