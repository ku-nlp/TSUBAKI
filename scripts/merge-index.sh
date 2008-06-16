#!/bin/sh

# 1���老�ȤΥ���ǥå����ǡ�����100����ñ�̤˥ޡ������륹����ץ�

# ���ʲ����ͤ��ѹ����뤳��
workspace=/tmp/mg_tsubaki_idx
scriptdir=$HOME/cvs/SearchEngine/scripts



id=$1
flist=$2
mkdir $workspace 2> /dev/null
cd $workspace

mkdir $id 2> /dev/null
cd $id

# ����ǥå����ǡ����򥳥ԡ�
for f in `egrep "i$id...idx.gz" $flist`
do
    echo scp $f ./
    scp $f ./
done
cd ..

# �ǥ�������ǥޡ���
echo "perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz"
perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $id -z -suffix idx.gz | gzip > $id.idx.gz
rm -r $id



fname=$id.idx.gz

# �Х��ʥ경
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname
perl -I $scriptdir $scriptdir/binarize_idx.pl -z -quiet $fname

# ʸ�����٤μ���
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# ʸ��Ĺ�ǡ����١����κ���
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
