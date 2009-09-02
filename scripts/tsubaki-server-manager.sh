#!/bin/sh

# $Id$

# tsubaki_server.plの起動／停止を管理するスクリプト
# tsubaki_server.plが停止している場合は、それを自動検出し再起動する

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

# 動作確認を行う間隔（秒）
INTERVAL=10
NICE=-4
SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi
MODULE_DIR=$TSUBAKI_DIR/perl
COMMAND=tsubaki_server.pl
USE_OF_SYNGRAPH="-syngraph"
MEM=4194304

# ログの出力先
LOGFILE=`grep SERVER_LOG_FILE $CONFIG_FILE | awk '{print $2}'`


start() {
    num=`ps auxww | grep tusbaki-server-manager.sh | grep -v share | grep start | grep -v grep | wc -l`
    if [ $num -gt 2 ] ; then
	echo Aleady running TSUBAKI SERVER MANAGER.
	exit
    fi

    while [ 1 ];
    do
	while read LINE
	do
	    if echo "$LINE" | grep -E '^[^\#]' >/dev/null 2>&1; then
		PORT=`echo $LINE | cut -f 3 -d ' '`
		pid=`ps auxww | grep $COMMAND | grep $PORT | grep -v grep`

		# $PORT番で起動しているプロセスがない場合
		if [ $? != "0" ] ; then
		    idxdir=`echo $LINE | cut -f 1 -d ' '`
		    anchor_idxdir=`echo $LINE | cut -f 2 -d ' '`
		    dlengthdbdir=$idxdir
		    OPTION="-idxdir $idxdir -idxdir4anchor $anchor_idxdir -dlengthdbdir $dlengthdbdir -port $PORT $USE_OF_SYNGRAPH"
		    if [ -e $idxdir ]; then
			echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=`date`\)
			echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=`date`\) >> $LOGFILE
			ulimit -Ss $MEM ; nice $NICE $PERL -I $CGI_DIR -I $SCRIPTS_DIR -I $MODULE_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND $OPTION &
		    fi
 		fi
	    fi
	done < $PORTS_FILE

	sleep $INTERVAL
    done
}


status_or_stop() {
    while read LINE
    do
	if echo "$LINE" | grep -E '^[^\#]' >/dev/null 2>&1; then
	    PORT=`echo $LINE | cut -f 3 -d ' '`
	    pid=`ps auxww | grep $COMMAND | grep $PORT | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 	    if [ -n "$pid" ]; then
 		if [ "$1" = "stop" ]; then
 		    kill -KILL $pid
		    echo [TSUBAKI SERVER] STOP\ \ \ \(host=`hostname`, port=$PORT, pid=$pid, time=`date`\)
		    echo [TSUBAKI SERVER] STOP\ \ \ \(host=`hostname`, port=$PORT, pid=$pid, time=`date`\) >> $LOGFILE
		else
		    echo [TSUBAKI SERVER STATUS] \(port\=$PORT host\=`hostname` pid\=$pid\)
		    echo [TSUBAKI SERVER STATUS] \(port\=$PORT host\=`hostname` pid\=$pid\) >> $LOGFILE
		fi
 	    fi
	fi
    done < $PORTS_FILE
}

restart() {
    status_or_stop stop
    start
}

halt() {
    status_or_stop stop

    pid=`ps auxww | grep tsubaki-server-manager | grep start | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
    if [ -n "$pid" ]; then
 	kill -KILL $pid
	echo [TSUBAKI SERVER] HALT\ \ \ \(pid=$pid, host=`hostname`, port=$PORT, time=`date`\)
	echo [TSUBAKI SERVER] HALT\ \ \ \(pid=$pid, host=`hostname`, port=$PORT, time=`date`\) >> $LOGFILE
    fi
}

case $1 in
    start)
	start
	;;
    stop)
	status_or_stop stop
	;;
    restart)
	restart
	;;
    status)
	status_or_stop status
	;;
    halt)
	halt
	;;
    *)
	echo "$0 start|stop|restart|status|halt"
	exit 1
esac
exit 0
