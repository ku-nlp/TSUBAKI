#!/bin/sh

# $Id$


# ★環境に従ってTSUBAKI_DIRを変更すること

# NICT
SUFFIX=
if [ `domainname` = 'crawl.kclab.jgn2.jp' ]; then
    TSUBAKI_DIR=$HOME/cvs/SearchEngine
    SUFFIX=.nict
else
    TSUBAKI_DIR=$HOME/cvs/SearchEngine
fi


# ★環境に従って以下の変数を変更すること

PERL=$HOME/local/bin/perl
SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi


# 起動時のオプション
OPTS="-string_mode -ignore_yomi"

CONFIGFILE=$TSUBAKI_DIR/cgi/configure$SUFFIX
COMMAND=snippet_make_server.pl
NICE=-4




start() {
    grep STANDARD_FORMAT_LOCATION $CONFIGFILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
    do
	host=`echo $LINE | cut -f 1 -d ' '`
	ports=`echo $LINE | cut -f 2 -d ' '`

	for port in `echo $ports | perl -pe 's/,/ /g'`
	do
	    command="ssh -f $host ulimit -Ss unlimited ; nice $NICE $PERL -I $CGI_DIR -I $SCRIPTS_DIR $SCRIPTS_DIR/$COMMAND -port $port $OPTS"
	    echo $command
	    $command
	done
    done
}

status_or_stop() {
    grep STANDARD_FORMAT_LOCATION $CONFIGFILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
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
