#!/bin/sh

# $Id$

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart"
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

# チェック間隔
INTERVAL=10

COMMAND=tsubaki_server.pl

# 使用メモリの上限
MEM_TH=`grep MAX_RATE_OF_MEMORY_USE $CONFIG_FILE | grep -v \# | awk '{print $2}'`
# ログの出力先
LOGFILE=`grep SERVER_LOG_FILE $CONFIG_FILE | grep -v \# | awk '{print $2}'`


start() {
    while [ 1 ];
    do
	for pid in `ps auxww | grep $COMMAND | grep -v grep | awk '{if ($4 > '$MEM_TH') print $2}'`
	do
	    PORT=`ps auxww | grep $COMMAND | grep -v grep | grep $pid | rev | cut -f 4 -d ' ' | rev`
	    echo KILL TSUBAKI SERVER BECAUSE OF MEMORY OVER! \(host=`hostname`, port=$PORT, max=$MEM_TH%, time=`date`\)
	    echo KILL TSUBAKI SERVER BECAUSE OF MEMORY OVER! \(host=`hostname`, port=$PORT, max=$MEM_TH%, time=`date`\) >> $LOGFILE
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
	usage
esac
exit 0
