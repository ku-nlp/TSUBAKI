#!/bin/sh

# 1���老�ȤΥ���ǥå����ǡ�����100����ñ�̤˥ޡ������륹����ץ�

# ���ʲ����ͤ��ѹ����뤳��
# workspace=/data2/skeiji/ntcir3/mg_syn_anchor_idx_080704
workspace=/data/local/skeiji/ntcir3/bin_idx/081109
scriptdir=$HOME/cvs/SearchEngine/scripts


N=25
id=$1
div=$2
flist=$3
dirid=$id$div
mkdir -p $workspace 2> /dev/null
cd $workspace

mkdir $dirid 2> /dev/null
cd $dirid

min=`expr $id * 100 + $div * $N`
max=`expr $min + $N`

# ����ǥå����ǡ����򥳥ԡ�
for f in `egrep "i$id...idx.gz" $flist`
do
    fid=`basename $f | cut -f 1 -d '.' | cut -f 2 -d 'i'`
    if [ $min -le $fid ]; then
	if [ $fid -lt $max ]; then
	    echo scp $f ./
	    scp -o "BatchMode yes" -o "StrictHostKeyChecking no" $f ./
	fi
    fi
done
cd ..


# ����åפ��ʤ��褦�˻��ͤ�����ꥵ���������¤���(max 4GB)
ulimit -m 4097152
ulimit -v 4097152

# �ǥ�������ǥޡ���
echo "perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $dirid -z -suffix idx.gz | gzip > $dirid.idx.gz"
perl -I $scriptdir $scriptdir/merge_sorted_idx.pl -dir $dirid -z -suffix idx.gz | gzip > $dirid.idx.gz
rm -fr $dirid



fname=$dirid.idx.gz

# �Х��ʥ경
echo perl -I $scriptdir $scriptdir/binarize_idx.pl -z -syn -quiet $fname
perl -I $scriptdir $scriptdir/binarize_idx.pl -z -syn -quiet $fname

# ʸ�����٤μ���
echo "perl $scriptdir/idx2df.pl $dirid.idx.gz"
perl $scriptdir/idx2df.pl $dirid.idx.gz

# ʸ��Ĺ�ǡ����١����κ���
echo "perl $scriptdir/make-dlength-db.perl -z $id.idx.gz"
perl $scriptdir/make-dlength-db.perl -z $dirid.idx.gz 

# echo rm $fname
# rm $fname

# echo gzip *.dat
# gzip *.dat

# forwardhost=`perl $HOME/work/mk_idx_ntcir3/mg_syn/get.pl $dirid`
# scp *.dat.gz $forwardhost
# scp offset* $forwardhost
