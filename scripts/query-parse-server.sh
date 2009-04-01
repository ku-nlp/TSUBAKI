#!/bin/sh

# $Id$

# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf


SCRIPTS_DIR=$TSUBAKI_DIR/scripts
MODULE_DIR=$TSUBAKI_DIR/perl
CGI_DIR=$TSUBAKI_DIR/cgi
COMMAND=query_parse_server.pl
NICE=-4
PORT=`grep PORT_OF_QUERY_PARSE_SERVER $CONFIG_FILE | grep -v \# | awk '{print $2}'`

start() {
    for h in `grep HOST_OF_QUERY_PARSE_SERVER $CONFIG_FILE | grep -v \# | awk '{print $2}' | perl -pe 's/,/ /g'`
    do
	echo ssh -f $h "ulimit -Ss unlimited ; nice $NICE $PERL -I $MODULE_DIR -I $CGI_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND $PORT"
	ssh -f $h "ulimit -Ss unlimited ; nice $NICE $PERL -I $MODULE_DIR -I $CGI_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND $PORT"
    done
}

status_or_stop() {
    for h in `grep HOST_OF_QUERY_PARSE_SERVER $CONFIG_FILE | grep -v \# | awk '{print $2}' | perl -pe 's/,/ /g'`
    do
	pid=`ssh -f $h ps auxww | grep $COMMAND | grep $PORT | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 	if [ "$1" = "stop" -a -n "$pid" ]; then
 	    ssh -f $h kill $pid
 	fi
	echo "$h: $pid"
    done
}

restart() {
    status_or_stop stop
    start
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
    *)
	echo "$0 start|stop|restart|status"
	exit 1
esac
exit 0
