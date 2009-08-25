#!/bin/sh

# $Id$

# SIDに対応するノードにデータをコピーする

# Usage:
# sh copy-data-to-host.sh -d /data/home/skeiji/tsubaki/test /data2/work/wisdom/newsid/xmls



# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

workspace=/tmp/$USER/cp.$USER
distdir=$workspace

while getopts d:T: OPT
do
    case $OPT in
	T)  workspace=$OPTARG/cp.$USER
	    ;;
	d)  distdir=$OPTARG
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
find $datadir_name -type f | head > $flist

# SIDに対応するホスト名を求める
perl -I$TSUBAKI_DIR/cgi $TSUBAKI_DIR/scripts/lookup-host-by-sid.perl -flist $flist | grep -v none > $mapfile

# 同じホストごとにデータをまとめる
cpshell=$workspace/cp.sh
awk '{print "cp --parents", $1, "'$workspace'/"$2}' $mapfile > $cpshell

cd $workspace
cut -f 2 -d ' ' $mapfile | sort -u | xargs mkdir -p

cd $datadir_prefix
sh $cpshell

cd $workspace
# コピーして展開する
for dir in `cut -f 2 -d ' ' $mapfile | sort -u`
do
    tgzf=${HOSTNAME}2${dir}.tgz
    host=$dir

    cd $dir
    tar czf $workspace/$tgzf $datadir_name
    cd ..

    scp $tgzf $host:$distdir
    ssh $host "cd $distdir ; tar xzf $tgzf"
    ssh $host "rm -f $distdir/$tgzf"
done
