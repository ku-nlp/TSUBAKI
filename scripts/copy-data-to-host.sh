#!/bin/sh

# $Id$

# SIDに対応するノードにデータをコピーする

# Usage:
# sh copy-data-to-host.sh -d /data/home/skeiji/tsubaki/test /data2/work/wisdom/newsid/xmls



# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf


workspace=/tmp/$USER/cp.$USER
distdir=/tmp/$USER/dist.$USER
hostid=`echo $HOSTNAME | cut -f 1 -d .`

while getopts d:T: OPT
do
    case $OPT in
	d)  distdir=$OPTARG
	    ;;
	T)  workspace=$OPTARG/cp.$USER
	    ;;
    esac
done
shift `expr $OPTIND - 1`


datadir=$1

datadir_prefix=`echo $datadir | xargs dirname`
datadir_name=`echo $datadir | xargs basename`

rm -fr $workspace 2> /dev/null
mkdir -p $workspace

flist=$workspace/flist
mapfile=$workspace/map

cd $datadir_prefix
find $datadir_name/ -type f > $flist

# SIDに対応するホスト名を求める
perl -I$TSUBAKI_DIR/cgi -I$TSUBAKI_DIR/scripts $TSUBAKI_DIR/scripts/lookup-host-by-sid.perl -flist $flist | grep -v $hostid | grep -v none > $mapfile

# 同じホストごとにデータをまとめる
cpshell=$workspace/cp.sh
awk '{print "mkdir -p '$workspace'/"$2"/`dirname "$1"` ; ln -s '$datadir_prefix'/"$1, "'$workspace'/"$2"/`dirname "$1"`"}' $mapfile > $cpshell

cd $workspace
cut -f 2 -d ' ' $mapfile | sort -u | xargs mkdir -p 2> /dev/null

cd $datadir_prefix
sh $cpshell

cd $workspace
# コピーして展開する
for dir in `cut -f 2 -d ' ' $mapfile | sort -u`
do
    sleeptime=`expr $RANDOM \% 120`
    sleep $sleeptime

    tgzf=${HOSTNAME}2${dir}.tgz
    host=$dir

    cd $dir
    tar czfh $workspace/$tgzf $datadir_name
    cd ..

    ssh $host "mkdir -p $distdir 2> /dev/null"
    scp $tgzf $host:$distdir
    ssh $host "cd $distdir ; tar xzfk $tgzf 2> /dev/null"
    ssh $host "rm -f $distdir/$tgzf"
    rm -f $workspace/$tgzf
done

rm -rf $workspace
