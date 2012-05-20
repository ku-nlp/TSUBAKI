#!/bin/sh

# indirからfindしたHTMLファイルを対象に、10桁IDのファイル名にコピーし、1ディレクトリ10000個ずつ格納する
# -n : dryrun
# -v : verbose

# 出力:
# outdir/000000/0000000000.html
# outdir/000000/0000000001.html
# ：
# outdir/000000/0000009999.html
# outdir/000001/0000000000.html
# outdir/000001/0000000001.html
# ：

usage() {
    echo "Usage: $0 [-e file_extention] [-n] [-v] indir outdir"
    exit 1
}

EXT=html
NUM_OF_HTMLS_IN_DIR=10000
DRYRUN=
COMMAND=cp
COMMAND_ARGS=

while getopts e:nvh OPT
do
    case $OPT in
	e)  EXT=$OPTARG
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

if [ ! -d $outtopdir ]; then
    ${DRYRUN}mkdir -p $outtopdir
    if [ -z "$DRYRUN" -a ! -d $outtopdir ]; then
	usage
    fi
fi

dcount=0
dstr=`printf %06d $dcount`
dstr4=`expr $dstr : "^\([0-9][0-9][0-9][0-9]\)"`
outdir=$outtopdir/$dstr4/$dstr
if [ ! -d $outdir ]; then
    ${DRYRUN}mkdir -p $outdir
fi
hcount=0

for f in `find $indir -name "*.$EXT"`
do
    destf=$outdir/$dstr`printf %04d $hcount`.$EXT
    ${DRYRUN}$COMMAND $COMMAND_ARGS $f $destf

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
