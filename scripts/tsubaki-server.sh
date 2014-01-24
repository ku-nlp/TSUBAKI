#!/bin/sh

# $Id$

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi
CONFIG_FILE=$TSUBAKI_DIR/conf/configure
USE_SSH_FLAG=1

usage() {
    echo "Usage: $0 [-c configure_file] [-s] start|stop|restart|status"
    exit 1
}

while getopts c:sh OPT
do
    case $OPT in
	c)  CONFIG_FILE=$OPTARG
	    echo $CONFIG_FILE | grep -q '^/' 2> /dev/null > /dev/null
	    if [ $? -ne 0 ]; then
		CONFIG_FILE=`pwd`/$CONFIG_FILE
	    fi
	    ;;
	s)  USE_SSH_FLAG=0
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

SCRIPTS_DIR=$TSUBAKI_DIR/scripts

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Not found: $CONFIG_FILE"
    usage
fi


call() {
    for h in `grep '^SEARCH_SERVERS' $CONFIG_FILE | awk '{print $2}' | LANG=C sort | LANG=C uniq`
    do
	if [ $USE_SSH_FLAG -eq 1 ]; then
	    ssh -f $h "sh $SCRIPTS_DIR/tsubaki-server-manager.sh -c $CONFIG_FILE -n $h $1"
	else
	    sh $SCRIPTS_DIR/tsubaki-server-manager.sh -c $CONFIG_FILE -s $1
	fi
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
	usage
esac
exit 0
