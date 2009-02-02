#!/bin/sh

# $Id$

# server の status を取得しつづけるデーモン

SLEEP_TIME=3600

while [ 1 ]
do
    perl -I../cgi watch-server-status.perl 2> /dev/null
    sleep $SLEEP_TIME
done
