#!/bin/sh

# $Id$

ARGS=
INDIR=
OUTDIR=
XML_SUFFIX=xml
IDX0_SUFFIX=idx0
BASEDIR=
GZIP=0
while getopts a:i:o:s:b:x:z OPT
do
    case $OPT in
	a)  ARGS=$OPTARG
	    ;;
	i)  INDIR=$OPTARG
	    ;;
	o)  OUTDIR=$OPTARG
	    ;;
	b)  BASEDIR=$OPTARG
	    ;;
	s)  XML_SUFFIX=$OPTARG
	    ;;
	x)  IDX0_SUFFIX=$OPTARG
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`


for f in $INDIR/*.$XML_SUFFIX; do
    basename=`basename $f .$XML_SUFFIX`
    perl -I$BASEDIR/cgi sf2term.pl $ARGS $f > $OUTDIR/$basename.$IDX0_SUFFIX
done
