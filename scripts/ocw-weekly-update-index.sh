#!/bin/sh

KDL_OCW_DIR=$HOME/kdl_ocw
TSUBAKI_DIR=$HOME/TSUBAKI
MAIN_DATADIR_TOP=$TSUBAKI_DIR/data.main.1305
SUB_DATADIR_TOP=$TSUBAKI_DIR/data.sub.1305

# set this according to the number of documents in the main index
START_DIR_ID=5
OCW_SITE=ocw.kyoto-u.ac.jp

export PATH=$PATH:/usr/local/bin
export PERL5LIB=$HOME/share/usr-x86_64/lib/perl5:$HOME/share/usr-x86_64/lib/perl5/site_perl:$HOME/share/usr-x86_64/lib64/perl5:$HOME/share/usr-x86_64/lib64/perl5/site_perl

if [ -f $TSUBAKI_DIR/.sub_index_last_date ]; then
    START_DATE=`cat $TSUBAKI_DIR/.sub_index_last_date`
else
    echo "Not found: $TSUBAKI_DIR/.sub_index_last_date"
    echo "Set START_DATE to 2013-05-24"
    START_DATE=2013-05-24
fi

LANGUAGE=
END_DATE=`date -d yesterday +%Y-%m-%d`
LIMIT=
RSSTYPE=content_

# retrieve new htmls
cd $KDL_OCW_DIR
./downloadFromRssAndProcess.sh -s $START_DATE -e $END_DATE -c
PROCESSED_DIR=$KDL_OCW_DIR/processed/ocw-diff_${RSSTYPE}${LANGUAGE}_${START_DATE}_${END_DATE}_${LIMIT}

if [ -d $PROCESSED_DIR/$OCW_SITE ]; then
    perl $TSUBAKI_DIR/scripts/make-url-sid-list.perl $PROCESSED_DIR/$OCW_SITE > $PROCESSED_DIR/urllist.txt

    # stop TSUBAKI servers
    $TSUBAKI_DIR/scripts/server-all.sh stop

    # update MAIN rmfiles
    if [ -f $MAIN_DATADIR_TOP/idx/0000/rmfiles ]; then
	cp -p $MAIN_DATADIR_TOP/idx/0000/rmfiles $MAIN_DATADIR_TOP/idx/0000/rmfiles.$START_DATE
    fi
    if [ ! -f $MAIN_DATADIR_TOP/idx/0000/url2sid ]; then
	perl $TSUBAKI_DIR/scripts/make-url-sid-list.perl $MAIN_DATADIR_TOP/html > $MAIN_DATADIR_TOP/idx/0000/url2sid
    fi
    perl $TSUBAKI_DIR/scripts/update-rmfiles.perl $MAIN_DATADIR_TOP/idx/0000 < $PROCESSED_DIR/urllist.txt > $MAIN_DATADIR_TOP/idx/0000/rmfiles.new
    mv -f $MAIN_DATADIR_TOP/idx/0000/rmfiles.new $MAIN_DATADIR_TOP/idx/0000/rmfiles

    # backup SUB index
    if [ -d $SUB_DATADIR_TOP ]; then
	if [ -d $SUB_DATADIR_TOP.$START_DATE ]; then
	    rm -rf $SUB_DATADIR_TOP.$START_DATE
	fi
	mkdir $SUB_DATADIR_TOP.$START_DATE
	tar -C $SUB_DATADIR_TOP -cf - html html.relocation.done idx src_doc xml xml_simple | tar -xvf - -C $SUB_DATADIR_TOP.$START_DATE
    fi

    # update SUB index
    if [ ! -d $SUB_DATADIR_TOP/src_doc ]; then
	mkdir -p $SUB_DATADIR_TOP/src_doc
    fi
    tar -C $PROCESSED_DIR -cf - $OCW_SITE | tar -xvf - -C $SUB_DATADIR_TOP/src_doc
    make -C $TSUBAKI_DIR/sf2index DATADIR=$SUB_DATADIR_TOP HTML_SRC_DIR=$SUB_DATADIR_TOP/src_doc clean
    make -C $TSUBAKI_DIR/sf2index DATADIR=$SUB_DATADIR_TOP HTML_SRC_DIR=$SUB_DATADIR_TOP/src_doc START_DIR_ID=$START_DIR_ID html
    make -C $TSUBAKI_DIR/sf2index DATADIR=$SUB_DATADIR_TOP HTML_SRC_DIR=$SUB_DATADIR_TOP/src_doc -j 8 indexing

    # update HTML/XML
    tar -C $SUB_DATADIR_TOP/html -cf - 0000 | tar -xvf - -C $MAIN_DATADIR_TOP/html
    tar -C $SUB_DATADIR_TOP/xml -cf - 0000 | tar -xvf - -C $MAIN_DATADIR_TOP/xml

    echo $END_DATE > $TSUBAKI_DIR/.sub_index_last_date

    # start TSUBAKI servers
    $TSUBAKI_DIR/scripts/server-all.sh start
else
    echo "Not found: $PROCESSED_DIR/$OCW_SITE"
    exit 1
fi
