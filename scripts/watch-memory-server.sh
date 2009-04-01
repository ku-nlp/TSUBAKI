#!/bin/sh

# $Id$

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

SCRIPTS_DIR=$TSUBAKI_DIR/scripts

call() {
    for n in `seq $HOSTS_START $HOSTS_END | awk '{printf "%0'$DEGIT'd\n", $1}'`
    do
	h=$HOSTS_PREFIX$n
	ssh -f $h "sh $SCRIPTS_DIR/watch-memory.sh $1"
    done
}

restart() {
    status_or_stop_or_halt halt
    start
}

case $1 in
    start)
	call start
	;;
    stop)
	call stop
	;;
    restart)
	call restart
	;;
    *)
	echo "$0 start|stop|restart"
	exit 1
esac
exit 0
