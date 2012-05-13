#!/bin/sh

# $Id$

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

# 起動時のオプション
OPTS="-string_mode -ignore_yomi -z -new_sf"
COMMAND=snippet_make_server.pl
NICE=-4

usage() {
    echo "Usage: $0 [-c configure_file] [-v] start|stop|restart|status"
    exit 1
}

while getopts c:vh OPT
do
    case $OPT in
	c)  CONFIG_FILE=$OPTARG
	    echo $CONFIG_FILE | grep -q '^/' 2> /dev/null > /dev/null
	    if [ $? != 0 ]; then
		CONFIG_FILE=`pwd`/$CONFIG_FILE
	    fi
	    ;;
	v)  OPTS="$OPTS -verbose"
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

# configureファイルから設定情報の読み込み
. $TSUBAKI_DIR/conf/tsubaki.conf

CGI_DIR=$TSUBAKI_DIR/cgi
SCRIPTS_DIR=$TSUBAKI_DIR/scripts

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Not found: $CONFIG_FILE"
    usage
fi


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
	usage
esac
exit 0
