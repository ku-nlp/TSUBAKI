#!/bin/sh

usage() {
    echo "Usage: $0 [-c configure_file] start|stop|restart|status"
    exit 1
}

SCRIPTS_DIR=`echo $0 | xargs dirname`

$SCRIPTS_DIR/tsubaki-server.sh $@
$SCRIPTS_DIR/snippet-server.sh $@
