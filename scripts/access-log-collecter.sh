#!/bin/sh

# $Id$

# apache のログファイルを取得しつづけるデーモン

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf


SLEEP_TIME=5

hostname=`grep LOADBALANCER_NAME $CONFIG_FILE | awk '{print $2}'`
access_log=`grep APACHE_ACCESS_LOG $CONFIG_FILE | awk '{print $2}'`
dist_dir=`grep DATA_DIR $CONFIG_FILE | awk '{print $2}'`

while [ 1 ]
do
    scp $hostname:$access_log $dist_dir/ 2> /dev/null
    sleep $SLEEP_TIME
done
