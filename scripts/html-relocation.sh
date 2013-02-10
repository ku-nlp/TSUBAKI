#!/bin/sh

# indirからfindしたHTMLファイルを対象に、10桁IDのファイル名にコピーし、1ディレクトリ10000個ずつ格納する
# マッピング(outdir/filename2sid)を出力
# -n : dryrun
# -v : verbose

# 出力:
# outdir/0000/000000/0000000000.html
# outdir/0000/000000/0000000001.html
# ：
# outdir/0000/000000/0000009999.html
# outdir/0000/000001/0000000000.html
# outdir/0000/000001/0000000001.html
# ：

usage() {
    echo "Usage: $0 [-e file_extention] [-s start_dir_id] [-n] [-v] indir outdir"
    exit 1
}

EXT=html
NUM_OF_HTMLS_IN_DIR=10000
DRYRUN=
COMMAND=cp
COMMAND_ARGS=
dcount=0

while getopts e:s:nvh OPT
do
    case $OPT in
	e)  EXT=$OPTARG
	    ;;
	s)  dcount=$OPTARG
	    ;;
	n)  DRYRUN="echo "
	    ;;
	v)  COMMAND_ARGS=-v
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

if [ -z "$1" -o -z "$2" ]; then
    usage
fi
indir=$1
outtopdir=$2
FILENAME2SID=$outtopdir/filename2sid

if [ ! -d $outtopdir ]; then
    ${DRYRUN}mkdir -p $outtopdir
    if [ -z "$DRYRUN" -a ! -d $outtopdir ]; then
	usage
    fi
fi

if [ -z "$DRYRUN" ]; then
    ${DRYRUN}: > $FILENAME2SID
fi

dstr=`printf %06d $dcount`
dstr4=`expr $dstr : "^\([0-9][0-9][0-9][0-9]\)"`
outdir=$outtopdir/$dstr4/$dstr
if [ ! -d $outdir ]; then
    ${DRYRUN}mkdir -p $outdir
fi
hcount=0

for srcf in `find $indir -name "*.$EXT"`
do
    basesrcf=`basename $srcf`
    basedestid=$dstr`printf %04d $hcount`
    basedestf=$basedestid.$EXT
    destf=$outdir/$basedestf
    if [ -z "$DRYRUN" ]; then
	echo "$basesrcf $basedestid" >> $FILENAME2SID
    fi
    ${DRYRUN}$COMMAND $COMMAND_ARGS $srcf $destf

    hcount=`expr $hcount + 1`
    if [ $hcount -eq $NUM_OF_HTMLS_IN_DIR ]; then
	dcount=`expr $dcount + 1`
	dstr=`printf %06d $dcount`
	dstr4=`expr $dstr : "^\([0-9][0-9][0-9][0-9]\)"`
	outdir=$outtopdir/$dstr4/$dstr
	if [ ! -d $outdir ]; then
	    ${DRYRUN}mkdir -p $outdir
	fi
	hcount=0
    fi
done
