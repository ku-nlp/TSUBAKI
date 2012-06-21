#!/bin/sh

# $Id$

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

# 起動時のオプション
OPTS="-string_mode -z -new_sf"
COMMAND=snippet_make_server.pl
NICE=-4
DATE=`LANG=C date`

usage() {
    echo "Usage: $0 [-c configure_file] [-v] start|stop|restart|status"
    exit 1
}

while getopts c:vh OPT
do
    case $OPT in
	c)  CONFIG_FILE=$OPTARG
	    echo $CONFIG_FILE | grep -q '^/' 2> /dev/null > /dev/null
	    if [ $? -ne 0 ]; then
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

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Not found: $CONFIG_FILE"
    usage
fi

PERL=`grep '^PERL' $CONFIG_FILE | awk '{print $2}'`
CGI_DIR=$TSUBAKI_DIR/cgi
SCRIPTS_DIR=$TSUBAKI_DIR/scripts

IGNORE_YOMI=`grep '^IGNORE_YOMI' $CONFIG_FILE | awk '{print $2}'`
if [ $IGNORE_YOMI -eq 1 ]; then
    OPTS="$OPTS -ignore_yomi"
fi

start() {
    grep '^SNIPPET_SERVERS' $CONFIG_FILE | awk '{print $2,$3}' | while read LINE
    do
	host=`echo $LINE | cut -f 1 -d ' '`
	ports=`echo $LINE | cut -f 2 -d ' '`

	for port in `echo $ports | perl -pe 's/,/ /g'`
	do
	    command="ssh -f $host $PERL -I $CGI_DIR -I $SCRIPTS_DIR $SCRIPTS_DIR/$COMMAND -port $port $OPTS"
	    echo [SNIPPET SERVER] START\ \ \(host=$host, port=$port, time=$DATE\)
	    $command
	done
    done
}

status_or_stop() {
    grep '^SNIPPET_SERVERS' $CONFIG_FILE | awk '{print $2,$3}' | while read LINE
    do
	host=`echo $LINE | cut -f 1 -d ' '`
	ports=`echo $LINE | cut -f 2 -d ' '`

	for port in `echo $ports | perl -pe 's/,/ /g'`
	do
	    pid=`ssh -f $host ps auxww | grep $COMMAND | grep $port | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 	    if [ -n "$pid" ]; then
		if [ "$1" = "stop" ]; then
 		    ssh -f $host kill $pid
		    echo [SNIPPET SERVER] STOP\ \ \ \(host=$host, port=$port, pid=$pid, time=$DATE\)
		else
		    echo [SNIPPET SERVER] STATUS\ \(host=$host, port=$port, pid=$pid, time=$DATE\)
		fi
	    fi
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
