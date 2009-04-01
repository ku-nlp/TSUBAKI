#!/bin/sh

# $Id$

# server の status を取得しつづけるデーモン

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi

SLEEP_TIME=3600

while [ 1 ]
do
    $PERL -I $CGI_DIR $SCRIPTS_DIR/watch-server-status.perl 2> /dev/null
    sleep $SLEEP_TIME
done
