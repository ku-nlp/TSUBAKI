#!/bin/sh

# $Id$

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

SCRIPTS_DIR=$TSUBAKI_DIR/scripts


call() {
    grep SEARCH_SERVERS_FOR_SYNGRAPH $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
    do
	h=`echo $LINE | cut -f 1 -d ' '`
	ssh -f $h "sh $SCRIPTS_DIR/tsubaki-server-manager.sh $1"
    done
}


case $1 in
    start)
	call start
	;;
    stop)
	call halt
	;;
    restart)
	call restart
	;;
    status)
	call status
	;;
    *)
	echo "$0 start|stop|restart|status"
	exit 1
esac
exit 0
