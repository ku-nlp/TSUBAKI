#!/bin/sh

# $Id$

# VERBOSE=-verbose
VERBOSE=

HOSTS_PREFIX=
HOSTS_START=
HOSTS_END=


# NICT
if [ `domainname` = 'crawl.kclab.jgn2.jp' ]; then
    HOSTS_PREFIX=iccc00
    HOSTS_START=4
    HOSTS_END=7
    TSUBAKI_DIR=$HOME/public_html/cgi-bin/SearchEngine-develop
else
    HOSTS_PREFIX=nlpc0
    HOSTS_START=2
    HOSTS_END=6
    TSUBAKI_DIR=$HOME/tsubaki-develop/SearchEngine
fi

SCRIPTS_DIR=$TSUBAKI_DIR/scripts
MODULE_DIR=$TSUBAKI_DIR/perl
CGI_DIR=$TSUBAKI_DIR/cgi
COMMAND=query_parse_server.pl
NICE=-4
PERL=$HOME/local/bin/perl


start() {
    for n in `seq $HOSTS_START $HOSTS_END`
    do
	h=$HOSTS_PREFIX$n
	ssh -f $h "ulimit -Ss unlimited ; nice $NICE $PERL -I $MODULE_DIR -I $CGI_DIR $SCRIPTS_DIR/$COMMAND"
    done
}

status_or_stop() {
    for n in `seq $HOSTS_START $HOSTS_END`
    do
	h=$HOSTS_PREFIX$n
	pid=`ssh -f $h ps auxww | grep $COMMAND | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
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
