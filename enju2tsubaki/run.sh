#!/bin/sh

dir=$HOME/share/tool/SearchEngine/enju2tsubaki

usage() {
    echo "Usage: $0 input.txt"
    exit 1
}

if [ -z "$1" -o ! -f "$1" ]; then
    usage
fi

enju -A -so < $1 > $1.enju.so
perl -I $dir $dir/enjuquery.pl $1.enju.so > $1.tsubaki1.so
$dir/StandOffManager/som export $1.tsubaki1.so $1 $1.tsubaki1.xml
perl $dir/addrawtext.pl $1.tsubaki1.xml
