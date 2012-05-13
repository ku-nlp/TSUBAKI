#!/bin/sh

# $Id$

# 検索サーバーの起動／停止を管理するスクリプト
# 検索サーバーが停止している場合は、それを自動検出し再起動する

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart|status|halt"
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

# 動作確認を行う間隔（秒）
INTERVAL=10
NICE=-4
SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi
MODULE_DIR=$TSUBAKI_DIR/perl
SLAVE_SERVER_DIR=$TSUBAKI_DIR/search
# COMMAND=tsubaki_server.pl
# EXEC_COMMAND="$PERL -I $CGI_DIR -I $SCRIPTS_DIR -I $MODULE_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND"
COMMAND=slave_server
EXEC_COMMAND=$SLAVE_SERVER_DIR/$COMMAND
USE_OF_SYNGRAPH="-syngraph"
MEM=4194304

# ログの出力先
LOGFILE=`grep SERVER_LOG_FILE $CONFIG_FILE | awk '{print $2}'`


start() {
    num=`ps auxww | grep $USER | grep tsubaki-server-manager.sh | grep -v ssh | grep start | grep -v grep | wc -l`
    if [ $num -gt 2 ] ; then
	echo Already running TSUBAKI SERVER MANAGER.
	exit
    fi

    while [ 1 ];
    do
	grep INDEX_LOCATION $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3,$4}' | while read LINE
	do
	    PORT=`echo $LINE | cut -f 3 -d ' '`
	    pid=`ps auxww | grep $COMMAND | grep $PORT | grep -v grep`

	    # $PORT番で起動しているプロセスがない場合
	    if [ $? != "0" ] ; then
		idxdir=`echo $LINE | cut -f 1 -d ' '`
		anchor_idxdir=`echo $LINE | cut -f 2 -d ' '`
		dlengthdbdir=$idxdir
		if [ $COMMAND = "slave_server" ]; then
		    OPTION="$idxdir $anchor_idxdir $PORT `hostname`"
		else
		    if [ $anchor_idxdir = "none" ]; then
			OPTION="-idxdir $idxdir -dlengthdbdir $dlengthdbdir -port $PORT $USE_OF_SYNGRAPH"
		    else
			OPTION="-idxdir $idxdir -idxdir4anchor $anchor_idxdir -dlengthdbdir $dlengthdbdir -port $PORT $USE_OF_SYNGRAPH"
		    fi
		fi

		if [ -d $idxdir ]; then
		    echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=`date`\)
		    echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=`date`\) >> $LOGFILE
		    if [ $COMMAND = "slave_server" ]; then
			ulimit -Ss $MEM ; nice $NICE $EXEC_COMMAND $OPTION
		    else
			ulimit -Ss $MEM ; nice $NICE $EXEC_COMMAND $OPTION &
		    fi
		fi
 	    fi
	done

	sleep $INTERVAL
    done
}


status_or_stop() {
    grep INDEX_LOCATION $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3,$4}' | while read LINE
    do
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
    done
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
	usage
esac
exit 0
