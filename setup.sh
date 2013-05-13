#!/bin/sh

CWD=$(pwd)

CONFIGURE_FILE_IN=$CWD/conf/configure.in
CONFIGURE_FILE=$CWD/conf/configure
SF2INDEX_MAKEFILE_IN=$CWD/sf2index/Makefile.in
SF2INDEX_MAKEFILE=$CWD/sf2index/Makefile
SEARCH_SH_IN=$CWD/search.sh.in
SEARCH_SH=$CWD/search.sh
INDEX_CGI_IN=$CWD/cgi/index.cgi.in
INDEX_CGI=$CWD/cgi/index.cgi
API_CGI_IN=$CWD/cgi/api.cgi.in
API_CGI=$CWD/cgi/api.cgi

# target names to be replaced
NAME_LIST="
PerlPath
SearchEnginePath
UtilsPath
SynGraphPath
WWW2sfPath
CalcSimilarityByCFPath
DetectBlocksPath
DocumentPath
SrcDocumentPath
CONFIGURE_FILE
MachineType
EnglishFlag
EnglishParserPath
EnglishParserOptions
EnglishTaggerPath
JavaPath
UseBlockTypeFlag
UsePredicateArgumentStructureFlag
PredicateArgumentDefinition
SearchServerHost
SearchServerPort
SnippetServerHost
SnippetServerPort
JUMANPrefix
KNPPrefix
HOME
HTMLExt
"

SearchEnginePath=$CWD
UtilsPath=$CWD/Utils
SynGraphPath=$CWD/SynGraph
WWW2sfPath=$CWD/WWW2sf
CalcSimilarityByCFPath=$CWD/CalcSimilarityByCF
DetectBlocksPath=$CWD/DetectBlocks
DocumentPath=$CWD/sample_doc/ja
SrcDocumentPath=$DocumentPath/src_doc
MachineType=`uname -m`
EnglishFlag=0
MaltParserPath=
StanfordParserPath=
JavaPath=/usr/bin/java
UseBlockTypeFlag=0
UsePredicateArgumentStructureFlag=0
PredicateArgumentDefinition=KNP
SearchServerHost=localhost
SearchServerPort=39999
SnippetServerHost=localhost
SnippetServerPort=59001
DocumentPathSpecifiedFlag=0
SrcDocumentPathSpecifiedFlag=0
HTMLExt=html

usage() {
    echo "Usage: $0 [-j|-e] [-U UtilsPath] [-S SynGraphPath] [-W WWW2sfPath] [-C CalcSimilarityByCFPath] [-D DetectBlocksPath] [-d DataPath] [-s SrcDocumentPath] [-c OutputConfFile] [-E SearchServerPort] [-N SnippetServerPort] [-n ServerName] [-T](UseBlockType) [-z](html.gz) [-m MaltParserPath] [-t TsuruokaTaggerPath] [-f StanfordParserPath] [-p](UsePredicateArgumentStructure)"
    exit 1
}

# getopts
while getopts c:ejU:S:W:C:D:d:s:E:N:n:Tzm:t:pf:h OPT
do
    case $OPT in
	c)  CONFIGURE_FILE=$OPTARG
	    ;;
	e)  EnglishFlag=1
	    ;;
	j)  EnglishFlag=0
	    ;;
        U)  UtilsPath=$OPTARG
            ;;
        S)  SynGraphPath=$OPTARG
            ;;
        W)  WWW2sfPath=$OPTARG
            ;;
	C)  CalcSimilarityByCFPath=$OPTARG
	    ;;
	D)  DetectBlocksPath=$OPTARG
	    ;;
        d)  if [ -d "$CWD/$OPTARG" ]; then
	        DocumentPath="$CWD/$OPTARG"
	    else
		DocumentPath=$OPTARG
	    fi
	    if [ $SrcDocumentPathSpecifiedFlag -eq 0 ]; then
		SrcDocumentPath=$DocumentPath/src_doc
	    fi
	    DocumentPathSpecifiedFlag=1
            ;;
        s)  if [ -d "$CWD/$OPTARG" ]; then
	        SrcDocumentPath="$CWD/$OPTARG"
	    else
		SrcDocumentPath=$OPTARG
	    fi
	    SrcDocumentPathSpecifiedFlag=1
            ;;
	E)  SearchServerPort=$OPTARG
	    ;;
	N)  SnippetServerPort=$OPTARG
	    ;;
	n)  SearchServerHost=$OPTARG
	    SnippetServerHost=$OPTARG
	    ;;
	T)  UseBlockTypeFlag=1
	    ;;
	z)  HTMLExt=html.gz
	    ;;
        m)  MaltParserPath=$OPTARG
            ;;
        t)  TsuruokaTaggerPath=$OPTARG
            ;;
	f)  StanfordParserPath=$OPTARG
	    ;;
	p)  UsePredicateArgumentStructureFlag=1
	    ;;
        h)  usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

CONFIGURE_FILE_BACKUP=$CONFIGURE_FILE.old
CONFIGURE_FILE_BASE=$CONFIGURE_FILE.base
CONFIGURE_FILE_DIFF=$CONFIGURE_FILE.diff
CONFIGURE_FILE_REJ=$CONFIGURE_FILE.rej

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
    echo "WWW2sf is not found. Please download WWW2sf (see README)."
    usage
fi

# check CalcSimilarityByCF
if [ ! -d "$CalcSimilarityByCFPath" ]; then
    echo "CalcSimilarityByCF is not found. Skipped CalcSimilarityByCF."
fi

# check DetectBlocks
if [ ! -d "$DetectBlocksPath" ]; then
    echo "DetectBlocks is not found. Skipped DetectBlocks."
fi

# check perl
PerlPath=`type perl 2> /dev/null | cut -f3 -d' '`
if [ -z "$PerlPath" ]; then
    echo "Perl is not found. Please set PATH to 'perl'."
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
    if [ -n "$MaltParserPath" ]; then
	# check MaltParser
	if [ -d $MaltParserPath ]; then
	    EnglishParserPath=$MaltParserPath
	    ParserJarPath=`echo $MaltParserPath/malt*.jar`
	    PredicateArgumentDefinition=Malt
	    if [ ! -f $ParserJarPath ]; then
	     	echo "Jar file (malt.jar) of Malt Parser is not found."
		exit 1
	    fi

	    ParserModelPath=`echo $MaltParserPath/engmalt*.mco`
	    if [ ! -f $ParserModelPath ]; then
	     	echo "Model file (engmalt) for Malt Parser is not found. Please place it to $MaltParserPath."
		exit 1
	    fi
	    ParserModelFile=`basename $ParserModelPath`
	    EnglishParserOptions="-jar $ParserJarPath -w $MaltParserPath -c $ParserModelFile -m parse"

            # check Java
	    JAVABIN=`type java 2> /dev/null | cut -f3 -d' '`
	    if [ ! -n "$JAVABIN" ]; then
		echo "Java is not found. Please install JDK to use MaltParser."
		exit 1
	    fi
	    JavaPath=$JAVABIN

	    if [ -x "$TsuruokaTaggerPath/tagger" ]; then
		EnglishTaggerPath=$TsuruokaTaggerPath
	    else
		echo "TsuruokaTagger is not found. Please specify valid path of TsuruokaTagger by -t option."
		usage
	    fi
	else
	    echo "MaltParser is not found in $MaltParserPath."
	    usage
	fi
    elif [ -n "$StanfordParserPath" ]; then
	# check Stanford Parser
	if [ -d $StanfordParserPath ]; then
	    EnglishParserPath=$StanfordParserPath
	    PredicateArgumentDefinition=Stanford

            # check Java
	    JAVABIN=`type java 2> /dev/null | cut -f3 -d' '`
	    if [ ! -n "$JAVABIN" ]; then
		echo "Java is not found. Please install JDK to use Stanford Parser."
		exit 1
	    fi
	    JavaPath=$JAVABIN
	else
	    echo "Stanford Parser is not found in $StanfordParserPath."
	    usage
	fi
    else
        # check Enju
	ENJUBIN=`type enju 2> /dev/null | cut -f3 -d' '`
	if [ ! -n "$ENJUBIN" ]; then
	    echo "Enju is not found. Please install Enju (see README)."
	    usage
	fi
	EnglishParserPath=$SearchEnginePath/enju2tsubaki
	PredicateArgumentDefinition=Enju
    fi
fi

# check source documents
if [ ! -d "$SrcDocumentPath" ]; then
    echo "Please specify correct SrcDocumentPath with -s option."
    usage
fi

# check Documents
if [ $DocumentPathSpecifiedFlag -eq 0 ]; then
    echo "Please specify DataPath with -d option."
    usage
fi
if [ ! -d "$DocumentPath" ]; then
    mkdir -p $DocumentPath
    if [ ! -d "$DocumentPath" ]; then
	echo "Cannot mkdir $DocumentPath"
	usage
    fi
fi

# take a diff of the configure file and backup it
if [ -f "$CONFIGURE_FILE" ]; then
    if [ -f "$CONFIGURE_FILE_BASE" ]; then
	if [ -f $CONFIGURE_FILE_REJ ]; then
	    rm -f $CONFIGURE_FILE_REJ
	fi
	diff -u $CONFIGURE_FILE_BASE $CONFIGURE_FILE > $CONFIGURE_FILE_DIFF
	if [ ! -s $CONFIGURE_FILE_DIFF ]; then
	    rm -f $CONFIGURE_FILE_DIFF
	fi
    fi

    mv -f $CONFIGURE_FILE $CONFIGURE_FILE_BACKUP
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
cp $CONFIGURE_FILE $CONFIGURE_FILE_BASE
# merge the diffrence that was manually added
if [ -f $CONFIGURE_FILE_DIFF ]; then
    patch -p0 < $CONFIGURE_FILE_DIFF
    if [ -f $CONFIGURE_FILE_REJ ]; then
	echo "the following changes are not merged into $CONFIGURE_FILE"
	cat $CONFIGURE_FILE_REJ
    fi
    rm -f $CONFIGURE_FILE_DIFF
fi
echo "done."
echo "generating '${SF2INDEX_MAKEFILE}' ... "
sed -e "${SED_STR}" $SF2INDEX_MAKEFILE_IN > $SF2INDEX_MAKEFILE
echo "done."
echo "generating '${SEARCH_SH}' ... "
sed -e "${SED_STR}" $SEARCH_SH_IN > $SEARCH_SH
chmod +x $SEARCH_SH
echo "done."
echo "generating '${INDEX_CGI}' ... "
sed -e "${SED_STR}" $INDEX_CGI_IN > $INDEX_CGI
chmod +x $INDEX_CGI
echo "done."
echo "generating '${API_CGI}' ... "
sed -e "${SED_STR}" $API_CGI_IN > $API_CGI
chmod +x $API_CGI
echo "done."
