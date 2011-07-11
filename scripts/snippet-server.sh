#!/bin/sh

# $Id$


# 設定ファイルの読み込み
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf


CGI_DIR=$TSUBAKI_DIR/cgi
SCRIPTS_DIR=$TSUBAKI_DIR/scripts

# 起動時のオプション
OPTS="-string_mode -ignore_yomi -z"
COMMAND=snippet_make_server.pl
NICE=-4




start() {
    grep STANDARD_FORMAT_LOCATION $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
    do
	host=`echo $LINE | cut -f 1 -d ' '`
	ports=`echo $LINE | cut -f 2 -d ' '`

	for port in `echo $ports | perl -pe 's/,/ /g'`
	do
	    command="ssh -f $host $PERL -I $CGI_DIR -I $SCRIPTS_DIR $SCRIPTS_DIR/$COMMAND -port $port $OPTS"
	    echo $command
	    $command
	done
    done
}

status_or_stop() {
    grep STANDARD_FORMAT_LOCATION $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
    do
	host=`echo $LINE | cut -f 1 -d ' '`
	ports=`echo $LINE | cut -f 2 -d ' '`

	for port in `echo $ports | perl -pe 's/,/ /g'`
	do
	    pid=`ssh -f $host ps auxww | grep $COMMAND | grep $port | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 	    if [ "$1" = "stop" -a -n "$pid" ]; then
 		ssh -f $host kill $pid
 	    fi
	    echo "$host: $pid"
	done
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
