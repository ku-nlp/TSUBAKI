#!/bin/sh

# URL�������ȥ�ǡ����١�����������륹����ץ�

# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf


indir=$1
ofile=$indir.url.title

rm $ofile 2> /dev/null

# $indir��10000��ʬ��ɸ��ե����ޥåȤ������줿�ǥ��쥯�ȥ꤬����ǥ��쥯�ȥ�
for d in `ls $indir`
do
    # $d��10000��ʬ��ɸ��ե����ޥåȤ������줿�ǥ��쥯�ȥ�
    echo "perl $scriptdir/extract-url-title.perl -z -url -title -dir $indir/$d >> $ofile"
    perl $scriptdir/extract-url-title.perl -z -url -title -dir $indir/$d >> $ofile
done

echo perl $scriptdir/make-url-title-cdbs.perl $ofile
perl $scriptdir/make-url-title-cdbs.perl $ofile

mv $ofile.title.cdb $indir.title.cdb
mv $ofile.url.cdb $indir.url.cdb
