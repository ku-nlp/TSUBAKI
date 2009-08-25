#!/bin/sh

# $Id$

confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

CGI_DIR=$TSUBAKI_DIR/cgi
DATA_DIR=$TSUBAKI_DIR/data

# SIDがどのホストで管理されているかを求め、ホストごとにSIDをまとめる
for sid in `cat $1`
do
    ret=`perl -I$CGI_DIR lookup-host-by-sid.perl $sid`
    host=`echo $ret | cut -f 2 -d ' '`
    echo $sid >> $host.remove-sid.$$
done


# ストップSIDリストに登録
CDIR=`pwd`
for f in `ls *.remove-sid.$$`
do
    host=`echo $f | cut -f 1 -d .`
    for dir in `cat $DATA_DIR/PORTS.SYN.NICT | grep -v \# | cut -f 1 -d ' '`
    do
	ssh $host "cat $CDIR/$f >> $dir/rmfiles"
    done
    rm -f $f
done
