#!/bin/sh

CWD=$(pwd)

CONFIGURE_FILE_IN=$CWD/cgi/configure.in
CONFIGURE_FILE=$CWD/cgi/configure
CONFIGURE_COPIED_FILE=$CWD/conf/configure
TSUBAKI_CONF_FILE_IN=$CWD/conf/tsubaki.conf.in
TSUBAKI_CONF_FILE=$CWD/conf/tsubaki.conf
SF2INDEX_MAKEFILE_IN=$CWD/sf2index/Makefile.in
SF2INDEX_MAKEFILE=$CWD/sf2index/Makefile
SEARCH_SH_IN=$CWD/search.sh.in
SEARCH_SH=$CWD/search.sh

# target names to be replaced
NAME_LIST="
SearchEnginePath
UtilsPath
SynGraphPath
WWW2sfPath
DocumentPath
CONFIGURE_FILE
MachineType
EnglishFlag
SearchServerHost
SearchServerPort
SnippetServerHost
SnippetServerPort
JUMANPrefix
KNPPrefix
HOME
"

SearchEnginePath=$CWD
UtilsPath=$CWD/Utils
SynGraphPath=$CWD/SynGraph
WWW2sfPath=$CWD/WWW2sf
DocumentPath=$CWD/sample_doc/ja
MachineType=`uname -m`
EnglishFlag=0
SearchServerHost=localhost
SearchServerPort=39999
SnippetServerHost=localhost
SnippetServerPort=59001

usage() {
    echo "Usage: $0 [-j|-e] [-u UtilsPath] [-s SynGraphPath] [-w WWW2sfPath] [-d StandardFormatPath] [-c OutputConfFile]"
    exit 1
}

# getopts
while getopts c:eju:s:w:d:h OPT
do
    case $OPT in
	c)  CONFIGURE_FILE=$OPTARG
	    ;;
	e)  EnglishFlag=1
	    ;;
	j)  EnglishFlag=0
	    ;;
        u)  UtilsPath=$OPTARG
            ;;
        s)  SynGraphPath=$OPTARG
            ;;
        w)  WWW2sfPath=$OPTARG
            ;;
        d)  if [ -d "$CWD/$OPTARG" ]; then
	        DocumentPath="$CWD/$OPTARG"
	    else
		DocumentPath=$OPTARG
	    fi
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
    echo "WWW2sf is not found. Skipped WWW2sf."
fi

# JUMAN/KNP is necessary for Japanese
if [ $EnglishFlag -eq 0 ]; then
    # check JUMAN
    JUMANBIN=`type juman 2> /dev/null | cut -f3 -d' '`
    if [ -n "$JUMANBIN" ]; then
	JUMANPrefix=`expr $JUMANBIN : "\(.*\)/bin/juman$"`
    else
	echo "JUMAN is not found. Please install JUMAN (see README)."
	usage
    fi

    # check KNP
    KNPBIN=`type knp 2> /dev/null | cut -f3 -d' '`
    if [ -n "$KNPBIN" ]; then
	KNPPrefix=`expr $KNPBIN : "\(.*\)/bin/knp$"`
    else
	echo "KNP is not found. Please install KNP (see README)."
	usage
    fi
else
    # check Enju
    ENJUBIN=`type enju 2> /dev/null | cut -f3 -d' '`
    if [ -n "$ENJUBIN" ]; then
	ENJUPrefix=`expr $ENJUBIN : "\(.*\)/bin/enju$"`
    else
	echo "Enju is not found. Please install Enju (see README)."
	usage
    fi
fi

# check Documents
if [ ! -d "$DocumentPath" ]; then
    echo "Document data are not found in $DocumentPath. Please specify correct path with -d option."
    usage
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
cp -f $CONFIGURE_FILE $CONFIGURE_COPIED_FILE
echo "done."
echo "generating '${TSUBAKI_CONF_FILE}' ... "
sed -e "${SED_STR}" $TSUBAKI_CONF_FILE_IN > $TSUBAKI_CONF_FILE
echo "done."
echo "generating '${SF2INDEX_MAKEFILE}' ... "
sed -e "${SED_STR}" $SF2INDEX_MAKEFILE_IN > $SF2INDEX_MAKEFILE
echo "done."
echo "generating '${SEARCH_SH}' ... "
sed -e "${SED_STR}" $SEARCH_SH_IN > $SEARCH_SH
chmod +x $SEARCH_SH
echo "done."
