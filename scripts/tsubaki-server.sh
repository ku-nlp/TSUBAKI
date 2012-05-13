#!/bin/sh

# $Id$

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart|status"
    exit 1
}

while getopts c:h OPT
do
    case $OPT in
	c)  CONFIG_FILE=$OPTARG
	    echo $CONFIG_FILE | grep -q '^/' 2> /dev/null > /dev/null
	    if [ $? != 0 ]; then
		CONFIG_FILE=`pwd`/$CONFIG_FILE
	    fi
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

# configureファイルから設定情報の読み込み
. $TSUBAKI_DIR/conf/tsubaki.conf

SCRIPTS_DIR=$TSUBAKI_DIR/scripts

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Not found: $CONFIG_FILE"
    usage
fi


call() {
    grep SEARCH_SERVERS_FOR_SYNGRAPH $CONFIG_FILE | grep -ve '^#' | awk '{print $2,$3}' | while read LINE
    do
	h=`echo $LINE | cut -f 1 -d ' '`
	ssh -f $h "sh $SCRIPTS_DIR/tsubaki-server-manager.sh -c $CONFIG_FILE $1"
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
