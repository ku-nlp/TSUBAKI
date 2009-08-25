#!/bin/sh

# $Id$

# ʸ�����٥ǡ����١�����������륹����ץ�


# ����ե�������ɤ߹���
confdir=`echo $0 | xargs dirname`/../conf
. $confdir/indexing.conf
workspace=$workspace_mkdfdb
mkdir -p $workspace 2> /dev/null
cd $workspace

source $SHELL_RCFILE

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
rm -f $workspace/merged.dffiles
echo done.
