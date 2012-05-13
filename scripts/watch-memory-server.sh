#!/bin/sh

# $Id$

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart"
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

SCRIPTS_DIR=$TSUBAKI_DIR/scripts

call() {
    for n in `seq $HOSTS_START $HOSTS_END | awk '{printf "%0'$DEGIT'd\n", $1}'`
    do
	h=$HOSTS_PREFIX$n
	ssh -f $h "sh $SCRIPTS_DIR/watch-memory.sh $1"
    done
}

restart() {
    status_or_stop_or_halt halt
    start
}

case $1 in
    start)
	call start
	;;
    stop)
	call stop
	;;
    restart)
	call restart
	;;
    *)
	usage
esac
exit 0
