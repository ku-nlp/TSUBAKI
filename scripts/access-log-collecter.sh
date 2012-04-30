#!/bin/sh

# $Id$

# apache のログファイルを取得しつづけるデーモン

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/cgi/configure

usage() {
    echo "Usage: $0 [-c configure_file]"
    exit 1
}

while getopts c:h OPT
do
    case $OPT in
	c)  CONFIG_FILE=$OPTARG
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

# configureファイルから設定情報の読み込み
. $TSUBAKI_DIR/conf/tsubaki.conf

SLEEP_TIME=5

hostname=`grep LOADBALANCER_NAME $CONFIG_FILE | awk '{print $2}'`
access_log=`grep APACHE_ACCESS_LOG $CONFIG_FILE | awk '{print $2}'`
dist_dir=`grep DATA_DIR $CONFIG_FILE | awk '{print $2}'`

while [ 1 ]
do
    scp $hostname:$access_log $dist_dir/ 2> /dev/null
    sleep $SLEEP_TIME
done
