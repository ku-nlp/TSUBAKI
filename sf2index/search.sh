#!/bin/sh

usage() {
    echo "$0 [-e] query"
    echo "\t-d dir: specify index_dir"
    echo "\t-e: english mode"
    echo "\t-f: specify query_file instead of query"
    exit 1
}

searchengine_dir=../
utils_dir=../../Utils
www2sf_dir=../../WWW2sf

file_mode=0
query_options=-syngraph
data_dir=sample_data
while getopts d:efh OPT
do
    case $OPT in
	d)  data_dir=$OPTARG
	    ;;
        e)  query_options=-english
            ;;
	f)  file_mode=1
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

if [ $file_mode -eq 0 ]; then
    query=$1
    if [ -z "$query" ]; then
	usage
    fi

    query_file=tmp_query_sexp_$$
    echo $query | perl -I$www2sf_dir/tool/perl -I$utils_dir/perl -I$searchengine_dir/cgi -I$searchengine_dir/perl -I$searchengine_dir/scripts $searchengine_dir/scripts/test-query-parser.perl $query_options > $query_file
else
    query_file=$1
fi

cat $query_file
../search/slave_server $data_dir $data_dir 39999 `hostname` -standalone < $query_file

if [ $file_mode -eq 0 ]; then
    rm -f $query_file
fi
