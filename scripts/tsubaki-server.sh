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
    TSUBAKI_DIR=$HOME/tsubaki/SearchEngine
    DEGIT=2
fi

SCRIPTS_DIR=$TSUBAKI_DIR/scripts



call() {
    for n in `seq $HOSTS_START $HOSTS_END | awk '{printf "%0'$DEGIT'd\n", $1}'`
    do
	h=$HOSTS_PREFIX$n
	ssh -f $h "sh $SCRIPTS_DIR/tsubaki-server-manager.sh $1"
    done
}


case $1 in
    start)
	call start
	;;
    stop)
	call halt
	;;
    restart)
	call restart
	;;
    status)
	call status
	;;
    *)
	echo "$0 start|stop|restart|status"
	exit 1
esac
exit 0
