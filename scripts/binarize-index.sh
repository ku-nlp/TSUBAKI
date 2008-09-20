#!/bin/sh

# ����ǥå����ǡ�����Х��ʥ경�����Ƽ�ǡ����١�����������륹����ץ�

# ���ʲ����ѿ����ͤ��Ѥ��뤳��
workspace=/tmp/bin_tsubaki
scriptdir=$HOME/cvs/SearchEngine/scripts

# SYNGRAPH����ǥå������ɤ�����Ƚ��
if [ $1 = "-syn" ];
then
    type=$1
    shift
fi

fp=$1
fname=`basename $fp`
id=`echo $fname | cut -f 1 -d '.'`

mkdir $workspace 2> /dev/null
cd $workspace

scp $fp ./

# �Х��ʥ경
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z $type -quiet $fname
perl -I $scriptdir $scriptdir/binarize_idx.pl -z $type -quiet $fname

# ʸ�����٤μ���
echo "perl $scriptdir/idx2df.pl $id.idx.gz"
perl $scriptdir/idx2df.pl $id.idx.gz

# ʸ��Ĺ�ǡ����١����κ���
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $id.idx.gz 

echo rm $fname
rm $fname
