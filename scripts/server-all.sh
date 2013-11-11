#!/bin/sh

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart|status"
    exit 1
}

SCRIPTS_DIR=`dirname $0`

$SCRIPTS_DIR/tsubaki-server.sh $@
$SCRIPTS_DIR/snippet-server.sh $@
$SCRIPTS_DIR/query-parse-server.sh $@
