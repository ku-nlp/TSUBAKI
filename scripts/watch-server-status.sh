#!/bin/sh

# $Id$

# server �� status ��������ĤŤ���ǡ����

TSUBAKI_DIR=`echo $0 | xargs dirname`/..
CONFIG_FILE=$TSUBAKI_DIR/cgi/configure

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

# configure�ե����뤫�����������ɤ߹���
. $TSUBAKI_DIR/conf/tsubaki.conf

SCRIPTS_DIR=$TSUBAKI_DIR/scripts
CGI_DIR=$TSUBAKI_DIR/cgi

SLEEP_TIME=3600

while [ 1 ]
do
    $PERL -I $CGI_DIR $SCRIPTS_DIR/watch-server-status.perl 2> /dev/null
    sleep $SLEEP_TIME
done
