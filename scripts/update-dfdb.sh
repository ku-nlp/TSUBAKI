#!/bin/sh

# ��ʸ�����٥ǡ����١����򹹿����륹����ץ�

# usage:
# sh update-dfdb.sh dfdbdir dftype newfile
#
# dfdbdir ... ���ߤ�DFDB�������Ƥ���ǥ��쥯�ȥ�
# dftype  ... DFDB�μ����word or dpnd��
# newfile ... �������ɲä�����DF�ǡ���
#
# ���ϥե�����
# df.$dftype.cdb.new ... �������������줿DFDB



# ���ʲ��Υ�����ץȤΥǥ��쥯�ȥ�����ѹ�
toolhome=$HOME/cvs/SearchEngine/scripts



# ����������
dfdbdir=$1
dftype=$2
newfile=$3

# cdb�ե���������Ƥ�ƥ����Ȥ��Ѵ�
for cdbf in `ls $dfdbdir/*.$dftype.*`
do
    echo perl $toolhome/cdb2txt.perl $cdbf
    perl $toolhome/cdb2txt.perl $cdbf
done

# ��¸�Υǡ����ȿ��ǡ�����ޡ���
echo perl $toolhome/merge_files.perl -n 0 $dfdbdir/*.$dftype.*.txt $newfile > df.$dftype.tmp.$$
perl $toolhome/merge_files.perl -n 0 $dfdbdir/*.$dftype.*.txt $newfile > df.$dftype.tmp.$$

# �ƥ����ȥǡ�����CDB��
echo perl $toolhome/make-cdb.perl df.$dftype.tmp.$$
perl $toolhome/make-cdb.pl df.$dftype.tmp.$$

# �����
rm $dfdbdir/*.txt
rm df.$dftype.tmp.$$

mv df.$dftype.tmp.$$.cdb df.$dftype.cdb.new
