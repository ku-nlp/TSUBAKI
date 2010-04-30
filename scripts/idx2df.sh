#!/bin/sh

# $Id$

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf

remove_blocktype_tag=0
workspace=$workspace_mgidx
while getopts rT: OPT
do
    case $OPT in
	r) remove_blocktype_tag=1
	    ;;
	T) workspace=$OPTARG
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

    mkdir -p $workspace/_tmp 2> /dev/null

    # タームの抽出
    zcat $idxf | awk '{print $1}' | perl -pe 's/^.*?://' > $kfile
    zcat $idxf | paste $kfile - | sort -T $workspace/_tmp | perl -pe 's/^.+\t//' | nkf -w > $sfile

    perl $scriptdir/idx2df.pl $sfile $opt

    rm $kfile
    rm $sfile
    rmdir $workspace/_tmp

    mv $sfile.df `echo $idxf | perl -pe 's/\.gz$//'`.df
else
    sfile=$1
    perl $scriptdir/idx2df.pl $sfile
fi