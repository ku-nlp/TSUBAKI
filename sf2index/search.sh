#!/bin/sh

usage() {
    echo "$0 [-e] query_string"
    echo "\t-e: english mode"
    exit 1
}

OtherOptions=
while getopts eh OPT
do
    case $OPT in
        e)  OtherOptions=-english
            ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

query=$1
UtilsDir=../../Utils

if [ -z "$query" ]; then
    usage
fi

perl -I $UtilsDir/perl -I ../scripts -I ../cgi -I ../perl ../scripts/tsubaki_test.pl -idxdir . -dlengthdbdir . -disable_query_processing $OtherOptions -query $query
