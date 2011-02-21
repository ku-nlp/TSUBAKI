#!/bin/sh

enju -A -so < $1 > $1.enju.so
perl enjuquery.pl $1.enju.so > $1.tsubaki1.so
./StandOffManager/som export $1.tsubaki1.so $1 $1.tsubaki1.xml
perl addrawtext.pl $1.tsubaki1.xml > $1.tsubaki.xml

