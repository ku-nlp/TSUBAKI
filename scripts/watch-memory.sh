#!/bin/sh

# $Id$

# チェック間隔
INTERVAL=10

COMMAND=tsubaki_server.pl

# NICT
if [ `domainname` = 'crawl.kclab.jgn2.jp' ]; then
    # ★環境にあわせて変えること
    TSUBAKI_DIR=$HOME/public_html/cgi-bin/SearchEngine
    CONFIG_FILE=$TSUBAKI_DIR/cgi/configure.nict
else
    TSUBAKI_DIR=$HOME/tsubaki/SearchEngine
    CONFIG_FILE=$TSUBAKI_DIR/cgi/configure
fi

# 使用メモリの上限
MEM_TH=`grep MAX_RATE_OF_MEMORY_USE $CONFIG_FILE | awk '{print $2}'`



start() {
    while [ 1 ];
    do
	for pid in `ps auxww | grep $COMMAND | grep -v grep | awk '{if ($4 > '$MEM_TH') print $2}'`
	do
	    PORT=`ps auxww | grep $COMMAND | grep -v grep | grep $pid | rev | cut -f 4 -d ' ' | rev`
	    echo KILL TSUBAKI SERVER BECAUSE OF MEMORY OVER! \(host=`hostname`, port=$PORT, max=$MEM_TH%, time=`date`\)
	    kill -KILL  $pid
	done

	sleep $INTERVAL
    done
}

stop() {
    for pid in `ps auxww | grep watch-memory | grep start | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
    do
	kill -KILL $pid
    done
}

restart() {
    start
    stop
}


case $1 in
    start)
	start
	;;
    stop)
	stop
	;;
    restart)
	restart
	;;
    *)
	echo "$0 start|stop|restart"
	exit 1
esac
exit 0
