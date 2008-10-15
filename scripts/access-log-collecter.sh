#!/bin/sh

# $Id$

# apache のログファイルを取得しつづけるデーモン

# NICT
if [ `domainname` = 'crawl.kclab.jgn2.jp' ]; then
    CONFIG=../cgi/configure.nict
else
    CONFIG=../cgi/configure
fi

SLEEP_TIME=5

hostname=`grep LOADBALANCER_NAME $CONFIG | awk '{print $2}'`
access_log=`grep APACHE_ACCESS_LOG $CONFIG | awk '{print $2}'`
dist_dir=`grep DATA_DIR $CONFIG | awk '{print $2}'`

while [ 1 ]
do
    scp $hostname:$access_log $dist_dir/ 2> /dev/null
    sleep $SLEEP_TIME
done
