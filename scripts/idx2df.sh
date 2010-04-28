#!/bin/sh

# $Id$

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf

remove_blocktype_tag=0
while getopts r OPT
do
    case $OPT in
	r) remove_blocktype_tag=1
	    ;;
    esac
done
shift `expr $OPTIND - 1`


if [ $remove_blocktype_tag -eq 1 ]
then
    idxf=$1
    kfile=$idxf.keys
    sfile=$idxf.sorted
    opt=-remove_tag

    # タームの抽出
    zcat $idxf | head -1000000 | awk '{print $1}' | nkf -e | rev | nkf -w > $kfile
    zcat $idxf | head -1000000 | paste $kfile - | nkf -e | sort | perl -pe 's/^.+\t//' | nkf -w > $sfile

    perl $scriptdir/idx2df.pl $sfile $opt

    rm $kfile
    rm $sfile

    mv $sfile.df `echo $idxf | perl -pe 's/\.gz$//'`.df
else
    sfile=$1
    perl $scriptdir/idx2df.pl $sfile
fi