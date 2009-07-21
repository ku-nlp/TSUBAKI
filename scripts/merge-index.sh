#!/bin/sh

# 1���老�ȤΥ���ǥå����ǡ�����100����ñ�̤˥ޡ������륹����ץ�

# usage: sh merge-index.sh [-syn] 000 /somewhere/flist


# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mgidx

source $SHELL_RCFILE


# ����åפ��ʤ��褦�˻��ͤ�����ꥵ���������¤���(max 4GB)
ulimit -m 4194304
ulimit -v 4194304


# SYNGRAPH�����ѥ���ǥå������ɤ����Υ����å�
type=
if [ $1 = "-syn" ];
then
    type="-syn"
    shift
fi
id=$1
flist=$2

# ��ȥǥ��쥯�ȥ�κ���
mkdir -p $workspace 2> /dev/null
cd $workspace

mkdir $id 2> /dev/null
cd $id


# ����ǥå����ǡ����򥳥ԡ�
for f in `egrep "i$id.*idx.gz" $flist`
do
    echo scp $f ./
    scp -o "BatchMode yes" -o "StrictHostKeyChecking no" $f ./
done
cd ..


# �ǥ�������ǥޡ���
echo "perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz"
perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz
rm -r $id


fname=$id.idx.gz

# �Х��ʥ경
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname $type
perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname $type

# ʸ�����٤μ���
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# ʸ��Ĺ�ǡ����١����κ���
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
