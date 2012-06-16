#!/bin/sh

# $Id$

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi
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

SCRIPTS_DIR=$TSUBAKI_DIR/scripts

call() {
    grep SEARCH_SERVERS $CONFIG_FILE | grep -ve '^#' | awk '{print $2}' | while read LINE
    do
	h=$LINE
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
