#!/bin/sh

TSUBAKI_DIR=`dirname $0`/..
echo $TSUBAKI_DIR | grep -q '^/' 2> /dev/null > /dev/null
if [ $? -ne 0 ]; then
    TSUBAKI_DIR=`pwd`/$TSUBAKI_DIR
fi

# Usage: $0 somewhere/average_doc_length.txt
average_doc_length_txt=$1

# default values
num_of_docs=" 100132750"
ave_doc_length=" 907"

if [ -s "$average_doc_length_txt" ]; then
    num_of_docs=`head -n 1 $average_doc_length_txt | cut -f 2 -d :`
    ave_doc_length=`tail -n 1 $average_doc_length_txt | cut -f 2 -d :`
fi

# overwrite search/common.h
perl -lpe "s/^\#define TOTAL_NUMBER_OF_DOCS \d+/#define TOTAL_NUMBER_OF_DOCS$num_of_docs/; s/^\#define AVERAGE_DOC_LENGTH \d+/#define AVERAGE_DOC_LENGTH$ave_doc_length/" -i $TSUBAKI_DIR/search/common.h
