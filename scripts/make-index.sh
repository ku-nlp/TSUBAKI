#!/bin/sh

# 1���ڡ������tgz���줿ɸ��ե����ޥåȤβ����饤��ǥå�������Ф��륹����ץ�

# usage: sh make-index.sh [-knp|-syn|-english] [-inlinks] iccc100:/data2/skeiji/embed_knp_and_syngraph_080512/s01573.tgz

# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mkidx

source $SHELL_RCFILE

SLEEPTIME=`expr $RANDOM % 600`
# sleep $SLEEPTIME

# �������륤��ǥå����Υ�����(-knp/-syn/-english)
type=$1

scheme=
block_type=-use_block_type

# -english�ΤȤ��ϡ�scheme��CoNLL�ˤ����֥�å������פϤ���������Ȥ�ʤ�
if [ $type = "-english" ]; then
    scheme="-scheme CoNLL"
    block_type=
fi

# �����󥯥���ǥå����κ������ɤ����Υ����å�
inlinks=
if [ $2 = "-inlinks" ];
then
    inlinks=$2
    shift
fi

# ��ʸ�������ɤ����Υ����å�
IPSJ=
if [ $2 = "-ipsj" ];
then
    IPSJ=$2
    shift
fi


fp=$2
id=`basename $fp | cut -f 2 -d 's' | cut -f 1 -d '.'`

xdir=s$id
idir=i$id

mkdir -p $workspace 2> /dev/null
cd $workspace

scp -o "BatchMode yes" -o "StrictHostKeyChecking no" -r $fp ./

mkdir -p $idir 2> /dev/null

echo tar xzf $xdir.tgz
tar xzf $xdir.tgz
rm -f $xdir.tgz

# ����åפ��ʤ��褦�˻��ͤ�����ꥵ���������¤���(max 4GB)
ulimit -m 4097152
ulimit -v 4097152


LOGFILE=$workspace/$xdir.log
touch $LOGFILE

# �ե�����ñ�̤ǥ���ǥå��������
# SYN�Ρ��ɤ�ޤ෸������ط��Ͻ�����5MB��ۤ���ɸ��ե����ޥåȤ������Ф��ʤ�
command="perl -I $scriptdir $scriptdir/make_idx.pl $type -in $xdir -out $idir -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z $inlinks -logfile $LOGFILE $IPSJ $scheme $block_type"
echo $command
until [ `tail -1 $LOGFILE | grep finish` ] ;
do
    $command
done
rm -fr $xdir


# 1���ڡ���ʬ�Υ���ǥå�����ޡ���

# N�鷺�ĥ����Ȥäƥޡ���
N=50
echo perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
perl $scriptdir/merge_idx.pl -dir $idir -n $N -z -compress
rm -fr $idir

# �ǥ�������ǥޡ���
tmpdir=$idir"_tmp"
mkdir -p $tmpdir 2> /dev/null
mv $idir.*.*gz $tmpdir

echo perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
perl $scriptdir/merge_sorted_idx.pl -dir ./$tmpdir -suffix gz -z | gzip > $idir.idx.gz
rm -fr $tmpdir

mkdir $workspace/finish 2> /dev/null
mv $idir.idx.gz finish/
