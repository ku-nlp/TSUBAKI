#!/bin/sh

# $Id$

# ʸ�����٥ǡ����١�����������륹����ץ�


# ���¹ԴĶ��˹�碌�ưʲ����ѿ����ѹ����Ƥ�������
workspace=.
scriptdir=$HOME/cvs/SearchEngine/scripts
utildir=$HOME/cvs/Utils/perl



opt=
while getopts z OPT
do
    case $OPT in
	z)  opt=" -z"
	    ;;
    esac
done
shift `expr $OPTIND - 1`



echo merging DF files...
perl $scriptdir/merge_dffiles.perl $opt $@ > $workspace/merged.dffiles
echo done.


echo making DF database...
perl -I $utildir $scriptdir/make-df-db.perl < $workspace/merged.dffiles
rm $workspace/merged.dffiles
echo done.
