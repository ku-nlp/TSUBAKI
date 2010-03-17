#!/bin/sh

# $Id$

confdir=`echo $0 | xargs dirname`/../conf
. $confdir/tsubaki.conf

CGI_DIR=$TSUBAKI_DIR/cgi
DATA_DIR=$TSUBAKI_DIR/data


hostfile=/
prefix=
config=
datadir=
while getopts h:p:c:d: OPT
do
    case $OPT in
	h)  hostfile=$OPTARG
	    ;;
	p)  prefix=$OPTARG
	    ;;
	c)  config=$OPTARG
	    ;;
	d)  datadir=$OPTARG
	    ;;
    esac
done
shift `expr $OPTIND - 1`

OPTION=
# �ɲ��ѥΡ��ɤǴ�������Ƥ���SID���������
if [ -f $hostfile ]; then
    . $config
    gxpc use ssh $prefix
    gxpc explore --children_hard_limit 1000 -t $hostfile
    gxpc e "mkdir -p ${workspace_alloc}"
    gxpc e "find ${datadir} -type f > ${workspace_alloc}/flist"
    gxpc e "perl -I${scriptdir}/../cgi -I${scriptdir} ${scriptdir}/lookup-host-by-sid.perl -sid_range ${sid_range} -flist ${workspace_alloc}/flist > ${workspace_alloc}/flist.w.host"
    gxpc e "cat ${workspace_alloc}/flist.w.host | grep -v \`hostname | cut -f 1 -d .\` | cut -f 1 -d ' ' | rev | cut -f 1 -d \/ | rev | cut -f 1 -d . | sort -n > ${workspace_alloc}/sids.other"
    gxpc e "cat ${workspace_alloc}/sids.other | awk '{print \"'\`hostname | cut -f 1 -d .\`'\", \$0}' > ${workspace_alloc}/sids.other.w.host"
    gxpc e cat ${workspace_alloc}/sids.other.w.host > sids.other.$$
    gxpc e "rm -r ${workspace_alloc}"
    gxpc quit

    OPTION="-sids_on_update_node sids.other.$$"
fi

# SID���ɤΥۥ��ȤǴ�������Ƥ��뤫���ᡢ�ۥ��Ȥ��Ȥ�SID��ޤȤ��
cat $1 | perl -I$CGI_DIR lookup-host-by-sid.perl $OPTION -stdin -save -suffix $$

# ���ȥå�SID�ꥹ�Ȥ���Ͽ
CDIR=`pwd`
for f in `ls *.remove-sid.$$`
do
    host=`echo $f | cut -f 1 -d .`
    for dir in `cat $DATA_DIR/PORTS.SYN.NICT | grep -v \# | cut -f 1 -d ' '`
    do
	ssh $host "cat $CDIR/$f >> $dir/rmfiles"
    done
    rm -f $f
done

rm sids.other.$$ 2> /dev/null
