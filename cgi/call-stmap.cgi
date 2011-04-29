#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use LWP::UserAgent;
use URI::Escape;
use XML::LibXML;
use Configure;


# binmode (STDOUT, ':utf8');
print header(-charset => 'utf-8');


my $CGI = new CGI();
my $QUERY = $CGI->param('query');
my $CONFIG = Configure::get_instance();
# 根拠サーチのパス
my $STMAP_HOME = "http://www.cl.ecei.tohoku.ac.jp/stmap";

&main();

sub main () {

    if ($QUERY) {
	sleep (1);
	print << "END_OF_HTML";
<HTML>
  <head>
    <META http-equiv="Content-Type" content="text/html;charset=UTF-8">

    <link type="text/css" rel="stylesheet" href="$STMAP_HOME/stmap_base.css">
    <link type="text/css" rel="stylesheet" href="$STMAP_HOME/evidence.css">
    <script type="text/javascript" src="$STMAP_HOME/popupwindow/jquery-1.2.6.min.js"></script>
    <script type="text/javascript" src="$STMAP_HOME/popupwindow/popupwindow-1.8.1.js"></script>
    <script type="text/javascript" src="$STMAP_HOME/wordBreak.js"></script> 
    <script type="text/javascript">parent.document.getElementsByName("owner")[0].rows = "70%,*";</script>
    <link type="text/css" rel="stylesheet" href="$STMAP_HOME/popupwindow/css/popupwindow.css" media="all" />

    <script type="text/javascript">
    function disp(divname) {
        var sflag=document.getElementById(divname).style.display;
END_OF_HTML

    print qq(var num = divname.match(/[0-9][0-9]*\$/);\n);
	print << "END_OF_HTML";
        var divname_base = divname.match(/^.*____/);

        if(sflag=="none") {
	    document.getElementById(divname).style.display="inline";
        } else {
	    for (i=1 ; i<=Number(num) ; i++) {
		var new_divname = divname_base + (i.toString());
		document.getElementById(new_divname).style.display="none";
	    }
        }
}

    </script>

  </head>
<BODY>
<DIV id="stmap" style="border: 0px solid red; height:100%;"><P>
<CENTER>
<IMG src='$CONFIG->{TSUBAKI_BASE_URL}/image/loading.gif' border='0' style='width:1em;'>&nbsp;クエリに賛成/反対する意見の根拠を検索結果より抽出中...<BR>
抽出に数分かかる場合がありますので，「検索する」ボタンを再度押したり，ブラウザのリロードをしたりせずにお待ちください。
</CENTER></DIV>
END_OF_HTML
&printAjax();
	print << "END_OF_HTML";
</BODY>
</HTML>
END_OF_HTML
    }

}




sub printAjax {
    my ($params) = @_;

    print << "END_OF_HTML";
<SCRIPT type="text/javascript" src="$CONFIG->{JAVASCRIPT_PATH}/prototype.js"></SCRIPT>
<SCRIPT>
new Ajax.Request(
    "$CONFIG->{TSUBAKI_BASE_URL}/stmap-wrapper.cgi",
    {
         onSuccess  : processResponse4Stmap,
         onFailure  : notifyFailure4Stmap,
         parameters : "query=$QUERY"
    }
);

function processResponse4Stmap(xhrObject)
    {
	Element.update('stmap', xhrObject.responseText);
    }

function notifyFailure4Stmap()
    {
        alert("An error occurred @ stmap!");
    }
</SCRIPT>
END_OF_HTML
}
