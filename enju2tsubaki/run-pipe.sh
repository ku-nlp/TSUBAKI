#!/bin/sh

dir=$HOME/share/tool/enju2tsubaki
input=$1

usage() {
    echo "Usage: $0 input.txt"
    exit 1
}

if [ -z "$input" -o ! -f "$input" ]; then
    usage
fi

enju -A -so < $input | perl -I $dir $dir/enjuquery.pl | $dir/StandOffManager/som export - $input - | perl $dir/addrawtext.pl
