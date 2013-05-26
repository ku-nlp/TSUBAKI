#!/bin/sh

# $Id$

# 検索サーバーの起動／停止を管理するスクリプト
# 検索サーバーが停止している場合は、それを自動検出し再起動する

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi
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

# 動作確認を行う間隔（秒）
INTERVAL=10
NICE=-4
SLAVE_SERVER_DIR=$TSUBAKI_DIR/search
# PERL=`grep '^PERL' $CONFIG_FILE | awk '{print $2}'`
# SCRIPTS_DIR=$TSUBAKI_DIR/scripts
# CGI_DIR=$TSUBAKI_DIR/cgi
# MODULE_DIR=$TSUBAKI_DIR/perl
# UTILS_DIR=`grep '^UTILS_PATH' $CONFIG_FILE | awk '{print $2}'`
# COMMAND=tsubaki_server.pl
# EXEC_COMMAND="$PERL -I $CGI_DIR -I $SCRIPTS_DIR -I $MODULE_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND"
COMMAND=slave_server
EXEC_COMMAND=$SLAVE_SERVER_DIR/$COMMAND
USE_OF_SYNGRAPH="-syngraph"
MEM=8388608
VMEM=16777216
DATE=`LANG=C date`

# ログの出力先
LOGFILE=`grep '^SERVER_LOG_FILE' $CONFIG_FILE | awk '{print $2}'`


start() {
    num=`ps auxww | grep $USER | grep $CONFIG_FILE | grep tsubaki-server-manager.sh | grep -v ssh | grep start | grep -v grep | wc -l`
    if [ $num -gt 2 ] ; then
	echo Already running TSUBAKI SERVER MANAGER.
	exit
    fi

    while [ 1 ];
    do
	grep '^SEARCH_SERVERS' $CONFIG_FILE | awk '{print $4,$5,$3}' | while read LINE
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
		    echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=$DATE\)
		    echo [TSUBAKI SERVER] START\ \ \(host=`hostname`, port=$PORT, time=$DATE\) >> $LOGFILE
		    if [ $COMMAND = "slave_server" ]; then
			ulimit -Ss $MEM -v $VMEM; nice $NICE $EXEC_COMMAND $OPTION
		    else
			ulimit -Ss $MEM -v $VMEM; nice $NICE $EXEC_COMMAND $OPTION &
		    fi
		fi
 	    fi
	done

	sleep $INTERVAL
    done
}


status_or_stop() {
    grep '^SEARCH_SERVERS' $CONFIG_FILE | awk '{print $3}' | while read LINE
    do
	PORT=$LINE
	pid=`ps auxww | grep $COMMAND | grep $PORT | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 	if [ -n "$pid" ]; then
 	    if [ "$1" = "stop" ]; then
 		kill -KILL $pid
		echo [TSUBAKI SERVER] STOP\ \ \ \(host=`hostname`, port=$PORT, pid=$pid, time=$DATE\)
		echo [TSUBAKI SERVER] STOP\ \ \ \(host=`hostname`, port=$PORT, pid=$pid, time=$DATE\) >> $LOGFILE
	    else
		echo [TSUBAKI SERVER] STATUS \(host\=`hostname`, port\=$PORT, pid\=$pid, time\=$DATE\)
		echo [TSUBAKI SERVER] STATUS \(host\=`hostname`, port\=$PORT, pid\=$pid, time\=$DATE\) >> $LOGFILE
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

    pid=`ps auxww | grep $USER | grep $CONFIG_FILE | grep tsubaki-server-manager.sh | grep -v ssh | grep start | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
    if [ -n "$pid" ]; then
 	kill -KILL $pid
	echo [TSUBAKI SERVER] HALT\ \ \ \(host=`hostname`, pid=$pid, time=$DATE\)
	echo [TSUBAKI SERVER] HALT\ \ \ \(host=`hostname`, pid=$pid, time=$DATE\) >> $LOGFILE
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
