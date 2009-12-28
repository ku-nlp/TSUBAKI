#!/bin/sh


# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf

source $SHELL_RCFILE


XMLFILES=$1
OUTDIR_PREFIX=$2
ONLY_INLINKS=$3
mkdir -p $workspace_mkidx/logfiles 2> /dev/null
LOGFILE=$workspace_mkidx/logfiles/logfile.of.`basename $XMLFILES`
MKIDX_OPTIONS="-syn -infiles $XMLFILES -position -compress -ignore_hypernym -ignore_yomi -ignore_syn_dpnd -skip_large_file 5242880 -z -logfile $LOGFILE -outdir_prefix $OUTDIR_PREFIX $ONLY_INLINKS"


# ���ե����뤬�ĤäƤ�����Ϻ��
touch $LOGFILE
rm $LOGFILE 2> /dev/null
touch $LOGFILE


# ����åפ��ʤ��褦�˻��ͤ�����ꥵ���������¤���(max 2GB)
ulimit -m $mem_size_for_mkidx
ulimit -v $mem_size_for_mkidx


# �ե�����ñ�̤�term�����
# SYN�Ρ��ɤ�ޤ෸������ط��Ͻ�����5MB��ۤ���ɸ��ե����ޥåȤ������Ф��ʤ�
until [ `tail -1 $LOGFILE | grep finish` ]
do
    perl -I $scriptdir $scriptdir/make_idx.pl $MKIDX_OPTIONS
done
