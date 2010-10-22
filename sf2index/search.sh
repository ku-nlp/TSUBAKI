#!/bin/sh

usage() {
    echo "$0 query_string"
    exit 1
}

query=$1
UtilsDir=../../Utils

if [ -z "$query" ]; then
    usage
fi

perl -I $UtilsDir/perl -I ../scripts -I ../cgi -I ../perl ../scripts/tsubaki_test.pl -idxdir . -dlengthdbdir . -disable_query_processing -query $query
