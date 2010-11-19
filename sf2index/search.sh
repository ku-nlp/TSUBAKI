#!/bin/sh

usage() {
    echo "$0 [-e] query_sexp_file"
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

if [ -z "$query" -o ! -f "$query" ]; then
    usage
fi

../search/slave_server . . 39999 `hostname` -standalone < $query
