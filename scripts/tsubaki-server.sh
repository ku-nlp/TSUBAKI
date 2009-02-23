#!/bin/sh

# $Id$

# VERBOSE=-verbose
VERBOSE=

HOSTS_PREFIX=
HOSTS_START=
HOSTS_END=

SUFFIX=

# NICT
if [ `domainname` = 'crawl.kclab.jgn2.jp' ]; then
    HOSTS_PREFIX=iccc
    HOSTS_START=11
    HOSTS_END=38
    DEGIT=3
    TSUBAKI_DIR=$HOME/public_html/cgi-bin/SearchEngine
    SUFFIX=.NICT
else
    HOSTS_PREFIX=nlpc
    HOSTS_START=34
    HOSTS_END=59
    DEGIT=2
    TSUBAKI_DIR=$HOME/tsubaki-develop/SearchEngine
fi

SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi
MODULE_DIR=$TSUBAKI_DIR/perl
UTILS_DIR=$HOME/cvs/Utils/perl
COMMAND=tsubaki_server.pl
NICE=-4
PERL=$HOME/local/bin/perl

# SYNGRAPH検索かどうかのチェック
if [ $1 = "-syn" ];
then
    PORTSFILE=$TSUBAKI_DIR/data/PORTS.SYN$SUFFIX
    USE_OF_SYNGRAPH="-syngraph"
    shift
else
    PORTSFILE=$TSUBAKI_DIR/data/PORTS.ORD$SUFFIX
    USE_OF_SYNGRAPH=
fi



start() {
    for n in `seq $HOSTS_START $HOSTS_END | awk '{printf "%0'$DEGIT'd\n", $1}'`
    do
	while read LINE
	do
	    if echo "$LINE" | grep -E '^[^\#]' >/dev/null 2>&1; then
		h=$HOSTS_PREFIX$n
		idxdir=`echo $LINE | cut -f 1 -d ' '`
		anchor_idxdir=`echo $LINE | cut -f 2 -d ' '`
		port=`echo $LINE | cut -f 3 -d ' '`
		dlengthdbdir=$idxdir
		OPTION="-idxdir $idxdir -dlengthdbdir $dlengthdbdir -port $port $USE_OF_SYNGRAPH $VERBOSE"
		if [ $anchor_idxdir != none ]; then
		    OPTION=$OPTION" -idxdir4anchor $anchor_idxdir"
		fi

	        ssh -f $h "nice $NICE $PERL -I $CGI_DIR -I $SCRIPTS_DIR -I $MODULE_DIR -I $UTILS_DIR $SCRIPTS_DIR/$COMMAND $OPTION"
	    fi
	done < $PORTSFILE
    done
}

status_or_stop() {
    for n in `seq $HOSTS_START $HOSTS_END | awk '{printf "%0'$DEGIT'd\n", $1}'`
    do
	while read LINE
	do
	    if echo "$LINE" | grep -E '^[^\#]' >/dev/null 2>&1; then
		h=$HOSTS_PREFIX$n
		PORT=`echo $LINE | cut -f 3 -d ' '`
		pid=`ssh -f $h ps auxww | grep $COMMAND | grep $PORT | grep -v grep | perl -lne "push(@list, \\$1) if /^$USER\s+(\d+)/; END {print join(' ', @list) if @list}"`
 		if [ "$1" = "stop" -a -n "$pid" ]; then
 		    ssh -f $h kill $pid
 		fi
		echo "$h: $pid"
	    fi
	done < $PORTSFILE
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
