#!/bin/sh

# 1���ڡ������tgz���줿ɸ��ե����ޥåȤβ����饤��ǥå�������Ф��륹����ץ�

# usage: sh make-index.sh [-knp|-syn] iccc100:/data2/skeiji/embed_knp_and_syngraph_080512/s01573.tgz

# ���ʲ����ͤ��ѹ����뤳��
workspace=/data2/skeiji/smallset/mkidx
scriptdir=$HOME/work/new-syngraph-test/mkidx/SearchEngine/scripts


# �������륤��ǥå����Υ�����(-knp/-syn)
type=$1
fp=$2
id=`basename $fp | cut -f 2 -d 's' | cut -f 1 -d '.'`

xdir=s$id
idir=i$id

mkdir $workspace 2> /dev/null
cd $workspace

scp -r $fp ./

mkdir $idir 2> /dev/null

echo tar xzf $xdir.tgz
tar xzf $xdir.tgz
rm $xdir.tgz

# ����åפ��ʤ��褦�˻��ͤ�����ꥵ���������¤���(max 2GB)
ulimit -m 2097152
ulimit -v 2097152

# �ե�����ñ�̤ǥ���ǥå��������
# SYN�Ρ��ɤ�ޤ෸������ط��Ͻ�����5MB��ۤ���ɸ��ե����ޥåȤ������Ф��ʤ�
echo perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z
perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z
rm -r $xdir


# 1���ڡ���ʬ�Υ���ǥå�����ޡ���

# N�鷺�ĥ����Ȥäƥޡ���
N=10
echo perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
rm -r $idir

# �ǥ�������ǥޡ���
tmpdir=$idir"_tmp"
mkdir $tmpdir 2> /dev/null
mv $idir.*.*gz $tmpdir

echo perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
rm -r $tmpdir
