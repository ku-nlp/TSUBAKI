#!/bin/sh

# $Id$

sflist=$1
for f in `cat $sflist`
do
  file=`basename $f`
  scp -o "BatchMode yes" -o "StrictHostKeyChecking no" $f ./
  tar tzf $file | grep xml.gz | rev | cut -f 1 -d \/ | rev | cut -f 1 -d .
  rm $file
done | sort | awk '{printf "%s %06d\n", $0, NR - 1}'
