#!/bin/sh

# $Id$

# server の status を取得しつづけるデーモン

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi
CONFIG_FILE=$TSUBAKI_DIR/conf/configure

usage() {
    echo "Usage: $0 [-c configure_file]"
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

PERL=`grep ^PERL $CONFIG_FILE | grep -v \# | awk '{print $2}'`
SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi

SLEEP_TIME=3600

while [ 1 ]
do
    $PERL -I $CGI_DIR $SCRIPTS_DIR/watch-server-status.perl 2> /dev/null
    sleep $SLEEP_TIME
done
