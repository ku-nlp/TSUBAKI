#!/usr/bin/env bash

# ./copy-idx-localdisk.sh -f /somewhere/TSUBAKI/idx -l /localdisk/TSUBAKI/ -i "0000 0001"

fileserver_base=
local_disk_base=

while getopts f:l:i: OPT
do  
    case $OPT in
        f)  fileserver_base=$OPTARG
            ;;
        l)  local_disk_base=$OPTARG
            ;;
        i)  ids=$OPTARG
            ;;
    esac
done
shift `expr $OPTIND - 1`

for id in $ids; do
    echo $id

    indir=$fileserver_base/$id
    outdir=$local_disk_base/idx/$id

    mkdir -p $outdir

    cp -pv $indir/did2title.cdb $outdir/
    cp -pv $indir/did2url.cdb $outdir/
    cp -pv $indir/sid2tid $outdir/
    cp -pv $indir/doc_length.txt $outdir/

    cp -pv $indir/idx.word.dat $outdir/
    cp -pv $indir/idx.dpnd.dat $outdir/

    cp -pv $indir/offset.word.cdb* $outdir/
    cp -pv $indir/offset.dpnd.cdb* $outdir/
done
