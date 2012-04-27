#!/bin/sh

CWD=$(pwd)

CONFIGURE_FILE_IN=$CWD/cgi/configure.in
CONFIGURE_FILE=$CWD/cgi/configure
TSUBAKI_CONF_FILE_IN=$CWD/conf/tsubaki.conf.in
TSUBAKI_CONF_FILE=$CWD/conf/tsubaki.conf
PORTS_FILE_IN=$CWD/data/PORTS.SYN.in
PORTS_FILE=$CWD/data/PORTS.SYN
SF2INDEX_MAKEFILE_IN=$CWD/sf2index/Makefile.in
SF2INDEX_MAKEFILE=$CWD/sf2index/Makefile
SF2INDEX_SEARCH_SH_IN=$CWD/sf2index/search.sh.in
SF2INDEX_SEARCH_SH=$CWD/sf2index/search.sh

NAME_LIST="
SearchEnginePath
UtilsPath
WWW2sfPath
SynGraphPath
MachineType
HOME
"

SearchEnginePath=$CWD
UtilsPath=$CWD/Utils
SynGraphPath=$CWD/SynGraph
WWW2sfPath=$CWD/WWW2sf
MachineType=`uname -m`

usage() {
    echo "Usage: $0 [-u UtilsPath] [-s SynGraphPath] [-w WWW2sfPath]"
    exit 1
}

# getopts
while getopts u:s:w:h OPT
do
    case $OPT in
        u)  UtilsPath=$OPTARG
            ;;
        s)  SynGraphPath=$OPTARG
            ;;
        w)  WWW2sfPath=$OPTARG
            ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

# check Utils
if [ ! -d "$UtilsPath" ]; then
    echo "Utils is not found. Please download Utils (see README)."
    usage
fi

# check SynGraph
if [ ! -d "$SynGraphPath" ]; then
    echo "SynGraph is not found. Please download SynGraph (see README)."
    usage
fi

# check WWW2sf
if [ ! -d "$WWW2sfPath" ]; then
    echo "WWW2sf is not found. Skipped WWW2sf (see README)."
fi


# make sed string
SED_STR=
for name in $NAME_LIST
do
    eval "val=\${${name}}"
    echo "setting \"$name\" to \"$val\""
    SED_STR=${SED_STR}"s#@${name}@#${val}#g;"
done

# generation
echo "generating '${CONFIGURE_FILE}' ... "
sed -e "${SED_STR}" $CONFIGURE_FILE_IN > $CONFIGURE_FILE
echo "done."
echo "generating '${TSUBAKI_CONF_FILE}' ... "
sed -e "${SED_STR}" $TSUBAKI_CONF_FILE_IN > $TSUBAKI_CONF_FILE
echo "done."
echo "generating '${PORTS_FILE}' ... "
sed -e "${SED_STR}" $PORTS_FILE_IN > $PORTS_FILE
echo "done."
echo "generating '${SF2INDEX_MAKEFILE}' ... "
sed -e "${SED_STR}" $SF2INDEX_MAKEFILE_IN > $SF2INDEX_MAKEFILE
echo "done."
echo "generating '${SF2INDEX_SEARCH_SH}' ... "
sed -e "${SED_STR}" $SF2INDEX_SEARCH_SH_IN > $SF2INDEX_SEARCH_SH
echo "done."
