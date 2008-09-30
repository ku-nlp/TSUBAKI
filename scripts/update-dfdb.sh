#!/bin/sh

# ��ʸ�����٥ǡ����١����򹹿����륹����ץ�

# usage: sh update-dfdb.sh dfdbdir dftype newfile
#
# dfdbdir ... ���ߤ�DFDB�������Ƥ���ǥ��쥯�ȥ�
# dftype  ... DFDB�μ����word or dpnd��
# newfile ... �������ɲä�����DF�ǡ���



# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf



# ����������
dfdbdir=$1
dftype=$2
newfile=$3

# cdb�ե���������Ƥ�ƥ����Ȥ��Ѵ�
for cdbf in `ls $dfdbdir/*.$dftype.*`
do
    echo perl $scriptdir/cdb2txt.perl $cdbf
    perl $scriptdir/cdb2txt.perl $cdbf
done

# ��¸�Υǡ����ȿ��ǡ�����ޡ���
echo perl $utildir/../scripts/merge_files.perl -n 0 $dfdbdir/*.$dftype.txt* $newfile > df.$dftype.tmp.$$
perl $utildir/../scripts/merge_files.perl -n 0 $dfdbdir/*.$dftype.txt* $newfile > df.$dftype.tmp.$$

# �ƥ����ȥǡ�����CDB��
echo perl -I $utildir $scriptdir/make-df-db.perl < df.$dftype.tmp.$$
perl -I $utildir $scriptdir/make-df-db.perl < df.$dftype.tmp.$$

# �����
rm $dfdbdir/*.txt*
rm df.$dftype.tmp.$$

