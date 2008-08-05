package Renderer;

# $Id$

use strict;
use utf8;
use Encode;
use Configure;
use POSIX qw(strftime);
use URI::Escape;
use XML::Writer;
use SnippetMakerAgent;
use CDB_File;
use Data::Dumper;

our $CONFIG = Configure::get_instance();

sub new {
    my($class, $called_from_API) = @_;
    my $this = {
	called_from_API => $called_from_API
    };

    bless $this;
}

sub DESTROY {
    my ($this) = @_;

    if (defined $this->{SNYONYM_DB}) {
	untie %$this->{SNYONYM_DB};
    }
}

sub printQuery {
    my ($this, $logger, $params, $size, $keywords, $status) = @_;

    if ($status eq 'busy') {
	printf qq(<DIV style="text-align: center; color: red;">ただいま検索サーバーが混雑しています。時間をおいてから再検索して下さい。</DIV>);
	return;
    }

    $this->{q2color} = $this->print_query($keywords);

    if ($logger->getParameter('hitcount') < 1) {
	print " を含む文書は見つかりませんでした。\n";
    } else {
	# ヒット件数の表示
	my $hitcount = $logger->getParameter('hitcount');
	while ($hitcount =~ s/(.*\d)(\d\d\d)/$1,$2/){};

	print " で検索された文書 $hitcount 件\n"; 
	if ($size > $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}) {
	    my $end = $params->{'start'} + $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'};
	    $end = $size if ($end > $size);
	    printf("のうち %d - %d 件目\n", $params->{'start'} + 1, $end);
	}
	print "</TD>\n";
    }
}

sub printSearchTime {
    my ($this, $logger, $params, $size, $keywords, $status) = @_;

    return if ($status eq 'busy');

    my $search_time = $logger->getParameter('search') + $logger->getParameter('parse_query') +  $logger->getParameter('snippet_creation');
    # 検索にかかった時間を表示 (★cssに変更)
    print qq(<TD width="400" style="text-align: right; background-color:#f1f4ff; mergin-left:0px;">\n);
    printf qq(<SPAN style="padding: 0.25em 0em; color: #f1f4ff;">(QP: %3.1f, DR: %3.1f, SC: %3.1f)</SPAN>\n), $logger->getParameter('parse_query'), $logger->getParameter('search'), $logger->getParameter('snippet_creation');

    if ($logger->getParameter('IS_CACHE')) {
	printf("%s: %3.1f (%s)\n", "検索時間", $search_time, "秒");
    } else {
	printf("%s: %3.1f [%s]\n", "検索時間", $search_time, "秒");
    }
#   print "</DIV>\n";
    print "</TD></TR></TABLE>\n";
}

sub printFooter {
    my ($this, $params, $hitcount, $current_page, $size, $opt) = @_;

    if ($opt->{kwic}) {
	print "<P>\n";
    } else {
	my $last_page_flag = 0;
	if ($hitcount >= $params->{'results'}) {
	    print "<DIV class='pagenavi'>検索結果ページ：";
	    my $num_of_search_results = ($CONFIG->{'NUM_OF_SEARCH_RESULTS'} > $CONFIG->{'NUM_OF_PROVIDE_SEARCH_RESULTS'}) ? $CONFIG->{'NUM_OF_PROVIDE_SEARCH_RESULTS'} : $CONFIG->{'NUM_OF_SEARCH_RESULTS'};
	    for (my $i = 0; $i < $num_of_search_results / $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}; $i++) {
		my $offset = $i * $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'};
		if ($size < $offset) {
		    last;
		} else {
		    $last_page_flag = 0;
		}
	    
		if ($offset == $current_page) {
		    print "<font color=\"brown\">" . ($i + 1) . "</font>&nbsp;";
		    $last_page_flag = 1;
		} else {
		    print "<a href=\"javascript:submit('$offset, $params->{query}')\">" . ($i + 1) . "</a>&nbsp;";
		}
	    }
	    print "</DIV>";
	}
	printf("<DIV class=\"bottom_message\">上の%d件と類似したページは除外されています。</DIV>\n", $size) if ($last_page_flag && $size < $hitcount && $size < $CONFIG->{'NUM_OF_SEARCH_RESULTS'});
    }


    # フッタ出力
    print << "END_OF_HTML";
    <SCRIPT language="javascript">
    <!--
    function submit(offset){
	document.forms['search'].start.value = offset;
	document.forms['search'].submit();

    }
    // -->
    </SCRIPT> 

    <DIV style="text-align:center;padding:1em;">
    TSUBAKI利用時の良かった点、問題点などご意見を頂けると幸いです。<br>
    ご意見は tsubaki あっと nlp.kuee.kyoto-u.ac.jp までお願い致します。
    <P>
    <DIV><B>&copy;2006 - 2008 黒橋研究室</B></DIV> 
    </DIV>
    </body>
    </html>
END_OF_HTML
}

sub makeToolTip {
    my ($this, $hyouki) = @_;

    my $tip;
    my %buf;
    unless (defined $this->{SYNONYM_DB}) {
	tie %{$this->{SYNONYM_DB}}, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . "<br>\n";
    }

    foreach my $synonym (split('\|', $this->{SYNONYM_DB}{$hyouki})) {
	if ($synonym =~ m!^([^/]+)/!) {
	    $synonym = $1;
	}
	$synonym =~ s/<[^>]+>//g;
	$buf{$synonym}++;
    }

    return decode('utf8', join(',', sort {$a cmp $b} keys %buf));
}

sub print_query {
    my($this, $keywords) = @_;

    print qq(<TABLE width="100%" border="0" class="querynavi"><TR><TD width="*" style="padding: 0.25em 1em; background-color:#f1f4ff;">\n);
    my @buf;
    for (my $i = 0; $i < scalar(@$keywords); $i++) {
	my $kwd = $keywords->[$i];
	push(@buf, sprintf (qq(<A href="#" style="font-weight: 900;" id="query%d">%s</A>), $i, $kwd->{rawstring}));
    }
    print join('&nbsp;', @buf);
}

sub print_query_verbose {
    my($this, $keywords) = @_;

    print qq(<DIV style="padding: 0.25em 1em; background-color:#f1f4ff;border-top: 1px solid gray;border-bottom: 1px solid gray;mergin-left:0px;">検索キーワード \();

    my $synonyms;
    foreach my $qk (@{$keywords}){
	if ($qk->{is_phrasal_search} > 0 && $qk->{sentence_flag} < 0) {
	    printf("<b style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$qk->{rawstring}</b>");
	} else {
	    my $words = $qk->{words};

	    my %pallette;
	    foreach my $reps (@$words) {
		foreach my $rep (@$reps) {
		    next if ($rep->{isContentWord} < 1 && $qk->{is_phrasal_search} < 1);

		    my $hyouki = $rep->{string};
		    if ($hyouki =~ /s\d+:/) {
			tie %$synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . "<br>\n" unless (defined $synonyms);

			# print $hyouki . "<br>\n";
			foreach my $synonym (split('\|', $synonyms->{$hyouki})) {
			    $synonym = decode('utf8', $synonym);

			    # 読みの削除
			    $synonym = $1 if ($synonym =~ m!^([^/]+)/!);

			    # 文法素性の削除
			    $synonym =~ s/<[^>]+>//g;

			    # print "$synonym $rep->{stylesheet}<br>\n";
			    $pallette{$synonym} = $rep->{stylesheet};
			}
			# print "<HR>\n";
		    }
		}
	    }

	    my %buf;
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @$words) {
		foreach my $rep (sort {$b->{string} cmp $a->{string}} @$reps) {
		    next if ($rep->{isContentWord} < 1 && $qk->{is_phrasal_search} < 1);

		    my $tip;
		    my $hyouki = $rep->{string};
		    if ($hyouki =~ /s\d+:/) {
			$tip = $this->makeToolTip($hyouki);

			$hyouki =~ s/s\d+://g;
			$hyouki = "&lt;$hyouki&gt;";
		    }

		    if (!exists $buf{$hyouki} || $hyouki =~ /&lt;/) {
			if (exists $pallette{$hyouki}) {
			    $rep->{stylesheet} = $pallette{$hyouki};
			} else {
			    printf qq(<span title="%s" style="%s">$hyouki</span>), $tip, $rep->{stylesheet};
			}

			$buf{$hyouki} = 1;
		    }
		}
	    }
	    
#	    my $dpnds = $qk->{dpnds};
# 	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$dpnds}){
# 		foreach my $rep (@{$reps}){
# 		    my $k_tmp  = $rep->{string};
# 		    $k_tmp =~ s/->/→/;
# 		    my $k_utf8 = encode('utf8', $k_tmp);
# 		    if(exists($cbuff{$rep->{string}})){
# 			printf("<span style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$rep->{string}}->{foreground}, $cbuff{$rep->{string}}->{background});
# 		    }else{
# 			if($color > 4){
# 			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
# 			    $cbuff{$rep->{string}}->{foreground} = 'white';
# 			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
# 			}else{
# 			    print "<span style=\"margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
# 			    $cbuff{$rep->{string}}->{foreground} = 'black';
# 			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
# 			}
# 			$color = (++$color%scalar(@HIGHLIGHT_COLOR));
# 		    }
# 		}
# 	    }
	}
    }

    untie %$synonyms if (defined $synonyms);
}

sub print_tsubaki_interface {
    my ($this, $params, $query) = @_;

    my $canvasName = 'canvas';
    my ($width, $height, $jscode) = $query->{keywords}[0]->getPaintingJavaScriptCode();

    print << "END_OF_HTML";
    <html>
	<head>
	<title>情報爆発プロジェクト 検索エンジン基盤 TSUBAKI</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="http://tsubaki.ixnlp.nii.ac.jp/tsubaki.common.css">
	<script language="JavaScript">
	var regexp = new RegExp("Gecko");
    if (navigator.userAgent.match(regexp)) {
	document.write("<LINK rel='stylesheet' type='text/css' href='http://tsubaki.ixnlp.nii.ac.jp/tsubaki.gecko.css'>");
    } else {
	document.write("<LINK rel='stylesheet' type='text/css' href='http://tsubaki.ixnlp.nii.ac.jp/tsubaki.ie.css'>");
    }

	</script>
	<script type="text/javascript" src="http://reed.kuee.kyoto-u.ac.jp/~skeiji/wz_jsgraphics.js"></script>
	<script type="text/javascript" src="http://reed.kuee.kyoto-u.ac.jp/~skeiji/prototype.js"></script>
	<script language="JavaScript">

function toggle_simpage_view (id, obj, open_label, close_label) {
    var disp = document.getElementById(id).style.display;
    if (disp == "block") {
        document.getElementById(id).style.display = "none";
        obj.innerHTML = open_label;
    } else {
        document.getElementById(id).style.display = "block";
        obj.innerHTML = close_label;
    }
}

function hide_query_result () {
    var baroon = document.getElementById("baroon");
    baroon.style.display = "none";
}

END_OF_HTML



    print << "END_OF_HTML";
    var jg;
function init () { 
    jg = new jsGraphics($canvasName);

END_OF_HTML

    for (my $i = 0; $i < scalar(@{$query->{keywords}}); $i++) {
	printf "Event.observe('query%d', 'mouseout',  hide_query_result);\n", $i;
	printf "Event.observe('query%d', 'mousemove', show_query_result%d);\n", $i, $i; 
    }
    print "}\n";

    my $colorOffset = 0;
    for (my $i = 0; $i < scalar(@{$query->{keywords}}); $i++) {
	my ($width, $height, $coffset, $jscode) = $query->{keywords}[$i]->getPaintingJavaScriptCode($colorOffset);
	$colorOffset = $coffset;

	printf "function show_query_result%d (e) {\n", $i;
	print "var x = Event.pointerX(e);\n";
	print "var y = Event.pointerY(e);\n";

	print "var baroon = document.getElementById('baroon');\n";
	print "baroon.style.display = 'block';\n";
	print "baroon.style.left = x;";
	print "baroon.style.top = y + 20;";

	print "var canvas = document.getElementById('canvas');\n";
	print "canvas.style.width = $width;\n";
	print "canvas.style.height = $height;\n";

	print $jscode;
	print "}\n";
    }

    print << "END_OF_HTML";
    </script>
	</head>
	<body style="padding: 0em; margin:0em; z-index:1;" onload="javascript:init();">
	  <TABLE cellpadding="0" cellspacing="0" border="0" id="baroon" style="display: none; z-index: 10; position: absolute; top: 100; left: 100;">
	    <TR>
	      <TD><IMG width="24" height="24" src="curve-top-left.png"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD><IMG width="24" height="24" src="curve-top-right.png"></TD>
	    </TR>
	    <TR>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD style="background-color:#ffffcc;" id="canvas"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	    </TR>
	    <TR>
	      <TD><IMG width="24" height="24" src="curve-bottom-left.png"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD><IMG width="24" height="24" src="curve-bottom-right.png"></TD>
	    </TR>
	  </TABLE>
END_OF_HTML

    my $host = `hostname`;
    print qq(<DIV style="font-size:smaller; width: 100%; text-align: right; padding:0em 0em 0em 0em;">\n);
    # print qq(<A href="http://www.infoplosion.nii.ac.jp/info-plosion/index.php"><IMG border="0" src="info-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html"><IMG style="padding: 0.5em 0em;" border="0" src="tutorial-logo.png"></A><BR>\n);
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/eval-tsubaki/whats.html">[おしらせ等]</A>\n); 
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html">[使い方ガイド]</A><BR>\n);
    print qq(</DIV>\n);

    # タイトル出力
    print qq(<TABLE width="100%" border="0"><TR><TD width="220" align="center" valign="middle" style="border: 0px solid red;">\n);
    printf ("<A href=%s><IMG border=0 src=./logo-mini.png></A></TD>\n", $CONFIG->{INDEX_CGI});


    # フォーム出力
    print qq(<TD width="*" align="left" valign="middle" style="border: 0px solid red; padding-top: 1em;">\n);
    print qq(<FORM name="search" method="GET" action="" enctype="multipart/form-data">\n);
    print qq(<INPUT type="hidden" name="start" value="0">\n);
    print qq(<INPUT type="text" name="q" value="$params->{'query'}" size="70">\n);
    print qq(<INPUT type="submit"name="送信" value="検索する"/>\n);
    print qq(<INPUT type="button"name="clear" value="クリア" onclick="document.all.INPUT.value=''"/>\n);

    if ($params->{develop_mode}) {
	print "<TABLE style=\"border=0px solid silver;padding: 0.25em;margin: 0.25em;\"><TR><TD>検索条件</TD>\n";
	if($params->{'logical_operator'} eq "OR"){
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/>全ての語を含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>いずれかの語を含む</LABEL></TD>\n";
	}elsif($params->{'logical_operator'} =~ /AND/){
	    if($params->{'force_dpnd'} > 0){
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\" checked/>全ての係り受けを含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/> 全ての語を含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\"/>いずれかの語を含む</LABEL></TD>\n";
	    }else{
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\" checked/> 全ての語を含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\"/>いずれかの語を含む</LABEL></TD>\n";
	    }
	}
	print "</TR>";

	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\">";
	if ($CONFIG->{DISABLE_SYNGRAPH_SEARCH}) {
	    print "<LABEL><INPUT type=\"checkbox\" name=\"syngraph\" disabled></INPUT><FONT color=silver>同義表現を考慮する</FONT></LABEL>";
	} else {
	    if ($params->{syngraph}) {
		print "<LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT><FONT color=black>同義表現を考慮する</FONT></LABEL>";
	    } else {
		print "<INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL><FONT color=black>同義表現を考慮する</FONT></LABEL>";
	    }
	}

	if ($params->{antonym_and_negation_expansion}) {
	    print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion" checked></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
	} else {
	    print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion"></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
	}

	if ($CONFIG->{DISABLE_KWIC_DISPLAY}) {
	    print qq(<INPUT type="checkbox" name="kwic" disabled></INPUT><FONT color=silver>KWIC表示</FONT></LABEL>);
	} else {
	    if ($params->{kwic}) {
		print qq(<INPUT type="checkbox" name="kwic" checked></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	    } else {
		print qq(<INPUT type="checkbox" name="kwic"></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	    }
	}
	print "</TD></TR></TABLE>\n";
    }
   
    print qq(</FORM>\n);
    print qq(</TD></TR></TABLE>\n);

    print "<CENTER>\n";
    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});
    print "</CENTER>\n";
}

sub print_tsubaki_interface_init {
    my ($this, $params) = @_;
    print << "END_OF_HTML";
    <html>
	<head>
	<title>情報爆発プロジェクト 検索エンジン基盤 TSUBAKI</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="./tsubaki.common.css">
	<script language="JavaScript">
	var regexp = new RegExp("Gecko");
    if (navigator.userAgent.match(regexp)) {
	document.write("<LINK rel='stylesheet' type='text/css' href='./tsubaki.gecko.css'>");
    } else {
	document.write("<LINK rel='stylesheet' type='text/css' href='./tsubaki.ie.css'>");
    }
	</script>
	<script language="JavaScript">
function toggle_simpage_view (id, obj, open_label, close_label) {
    var disp = document.getElementById(id).style.display;
    if (disp == "block") {
        document.getElementById(id).style.display = "none";
        obj.innerHTML = open_label;
    } else {
        document.getElementById(id).style.display = "block";
        obj.innerHTML = close_label;
    }
}

</script>
	</head>
	<body style="margin:0em;">
END_OF_HTML

my $host = `hostname`;
#    print "TSUBAKI on $host<BR>\n";
    # タイトル出力
    print qq(<DIV style="font-size:smaller; text-align:right;margin:0.5em 1em 0em 0em;">\n);
    # print qq(<A href="http://www.infoplosion.nii.ac.jp/info-plosion/index.php"><IMG border="0" src="info-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html"><IMG style="padding: 0.5em 0em;" border="0" src="tutorial-logo.png"></A><BR>\n);
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/eval-tsubaki/whats.html">[おしらせ等]</A>\n); 
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html">[使い方ガイド]</A><BR>\n);
    print qq(</DIV>\n);

    print qq(<CENTER style="maring:1em; padding:1em;">\n);
    printf ("<A href=%s><IMG border=0 src=./logo.png></A><P>\n", $CONFIG->{INDEX_CGI});

    # フォーム出力
    print qq(<FORM name="search" method="GET" action="$CONFIG->{INDEX_CGI}">\n);
    print "<INPUT type=\"hidden\" name=\"start\" value=\"0\">\n";
    print "<INPUT type=\"text\" name=\"q\" value=\'$params->{'query'}\' size=\"90\">\n";
    print "<INPUT type=\"submit\"name=\"送信\" value=\"検索する\"/>\n";
    print "<INPUT type=\"button\"name=\"clear\" value=\"クリア\" onclick=\"document.all.q.value=''\"/>\n";

    if ($params->{develop_mode}) {
	print "<TABLE style=\"border=0px solid silver;padding: 0.25em;margin: 0.25em;\"><TR><TD>検索条件</TD>\n";
	if ($params->{'logical_operator'} eq "OR") {
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/>全ての語を含む</LABEL></TD>\n";
	    print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>いずれかの語を含む</LABEL></TD>\n";
	} elsif ($params->{'logical_operator'} eq "AND") {
	    if ($params->{'force_dpnd'} > 0) {
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\" checked/>全ての係り受けを含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/> 全ての語を含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\"/>いずれかの語を含む</LABEL></TD>\n";
	    } else {
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\" checked/> 全ての語を含む</LABEL></TD>\n";
		print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\"/>いずれかの語を含む</LABEL></TD>\n";
	    }
	}
	print "</TR>";

	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\">";
	if ($CONFIG->{DISABLE_SYNGRAPH_SEARCH}) {
	    print "<LABEL><INPUT type=\"checkbox\" name=\"syngraph\" disabled></INPUT><FONT color=silver>同義表現を考慮する</FONT></LABEL>";
	} else {
	    if ($params->{syngraph}) {
		print "<LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT><FONT color=black>同義表現を考慮する</FONT></LABEL>";
	    } else {
		print "<INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL><FONT color=black>同義表現を考慮する</FONT></LABEL>";
	    }
	}

	if ($params->{antonym_and_negation_expansion}) {
	    print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion" checked></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
	} else {
	    print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion"></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
	}

	if ($CONFIG->{DISABLE_KWIC_DISPLAY}) {
	    print qq(<INPUT type="checkbox" name="kwic" disabled></INPUT><FONT color=silver>KWIC表示</FONT></LABEL>);
	} else {
	    if ($params->{kwic}) {
		print qq(<INPUT type="checkbox" name="kwic" checked></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	    } else {
		print qq(<INPUT type="checkbox" name="kwic"></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	    }
	}

	print "</TD></TR></TABLE>\n";
    }
    
    print "</FORM>\n";

    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});

    print "</CENTER>";

    # フッターの表示
    $this->printFooter($params, 0, 0, 0);
}

sub get_uri_escaped_query {
    my ($this, $query) = @_;
    # キャッシュページで索引語をハイライトさせるため、索引語をuri_escapeした文字列を生成する

    my @buf2;
    my $pos = 0;
    foreach my $qk (@{$query->{keywords}}) {
 	my $words = $qk->{words};
 	foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}) {
	    my %buf1;
	    foreach my $rep (sort {$b->{string} cmp $a->{string}} @{$reps}) {
		next if($rep->{isContentWord} < 1 && $rep->{is_phrasal_search} < 1);
		my $string = $rep->{string};

		# next if ($string =~ /s\d+:/);

		# $string =~ s/s\d+://; # SynID の削除
		$string =~ s/\/.+$//; # 読みがなの削除

		next if ($string =~ /<^>]+?>/);
		next if (exists $buf1{$string});

		$buf1{$string}++;
	    }
	    push(@buf2, join(";", sort {$a cmp $b} keys %buf1));
	}
    }

    my $search_k = join(",", @buf2);
    my $uri_escaped_search_keys = &uri_escape(encode('utf8', $search_k));
    return $uri_escaped_search_keys;
}

sub get_uri_escaped_query2 {
    my ($this, $query) = @_;
    # キャッシュページで索引語をハイライトさせるため、索引語をuri_escapeした文字列を生成する
    my $search_k;
    foreach my $qk (@{$query->{keywords}}) {
	my $words = $qk->{words};
	foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}) {
	    foreach my $rep (sort {$b->{string} cmp $a->{string}} @{$reps}) {
		next if($rep->{isContentWord} < 1 && $rep->{is_phrasal_search} < 1);
		my $string = $rep->{string};
		
		$string =~ s/s\d+://; # SynID の削除
		$string =~ s/\/.+$//; # 読みがなの削除
		$search_k .= "$string:";
	    }
	}
    }
    chop($search_k);
    my $uri_escaped_search_keys = &uri_escape(encode('utf8', $search_k));
    return $uri_escaped_search_keys;
}

sub get_snippets {
    my ($this, $opt, $result, $query, $from, $end) = @_;

    my @dids = ();
    # スニペット生成のため、類似ページも含め、表示されるページのIDを取得
    for (my $rank = $from; $rank < $end; $rank++) {
	push(@dids, sprintf("%09d", $result->[$rank]{did}));
	unless ($this->{called_from_API}) {
	    foreach my $sim_page (@{$result->[$rank]{similar_pages}}) {
		# push(@dids, sprintf("%09d", $sim_page->{did}));
	    }
	}
    }

    my $sni_obj = new SnippetMakerAgent();
    $sni_obj->create_snippets($query, \@dids, { discard_title => 1,
						syngraph => $opt->{'syngraph'},
						# options for snippet creation
						window_size => 5,

						# options for kwic
						kwic => $opt->{kwic},
						kwic_window_size => $opt->{kwic_window_size},
						use_of_repname_for_kwic => $opt->{use_of_repname_for_kwic},
						use_of_katuyou_for_kwic => $opt->{use_of_katuyou_for_kwic},
						use_of_dpnd_for_kwic => $opt->{use_of_dpnd_for_kwic},
						use_of_huzokugo_for_kwic => $opt->{use_of_huzokugo_for_kwic},
						debug => $opt->{debug}});

    if ($opt->{kwic}) {
	# KWICを取得
	if ($this->{called_from_API}) {
	    return $sni_obj->makeKWICForAPICall();
	} else {
	    return $sni_obj->makeKWICForBrowserAccess({sort_by_contextR => $opt->{sort_by_CR}});
	}
    } else {
	# スニペッツを取得
	my $did2snippets =  $sni_obj->get_snippets_for_each_did($query, {highlight => $opt->{highlight}});
	return $did2snippets;
    }
}

sub printSearchResultForBrowserAccess {
    my ($this, $params, $results, $query, $logger, $status) = @_;

    ##########################
    # ロゴ、検索フォームの表示
    ##########################
    $this->print_tsubaki_interface($params, $query);


    my $size = scalar(@$results);
    my $start = $params->{start};
    my $end = ($start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE} > $size) ? $size : $start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE};


    ##################
    # 検索クエリの表示
    ##################
    $this->printQuery($logger, $params, $size, $query->{keywords}, $status);


    ############################
    # 必要ならばスニペットを生成
    ############################
    my $did2snippets;
    if (!$params->{no_snippets} && !$params->{kwic}) {
	# 検索結果（表示分）についてスニペットを生成
	$did2snippets = $this->get_snippets($params, $results, $query, $start, $end);
    }
    # スニペット生成に要した時間をロギング
    $logger->setTimeAs('snippet_creation', '%.3f');


    ################
    # 検索時間の表示
    ################
    $this->printSearchTime($logger, $params, $size, $query->{keywords}, $status);


    ##################################
    # KWICまたは通常版の検索結果を表示
    ##################################
    ($params->{kwic}) ? $this->printKwicView($params, $results, $query) : $this->printOrdinarySearchResult($logger, $params, $results, $query, $start, $end, $did2snippets);


    ################
    # フッターの表示
    ################
    $this->printFooter($params, $logger->getParameter('hitcount'), $start, $size, $params);


    ############################
    # 表示に要した時間のロギング
    ############################
    $logger->setTimeAs('print_result', '%.3f');
}


sub printKwicView {
    my ($this, $params, $results, $query) = @_;

    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);
    my $kwics = $this->get_snippets($params, $results, $query, 0, $params->{num_of_pages_for_kwic_view});

    my %buf;
    my $output = "<CENTER><TABLE border=0>\n";

    my $url = $params->{URI};
    $url =~ s/\&?sort_by_CR=\d//;
    my $link4contextL = $url . '&sort_by_CR=0';
    my $link4contextR = $url . '&sort_by_CR=1';

    $output .= ($params->{sort_by_CR}) ?
	sprintf qq(<TR><TD>&nbsp;</TD><TD align="center"><A href="%s">コンテキストの左側でソートする</A></TD><TD>&nbsp;</TD><TD>&nbsp;</TD></TR>\n), $link4contextL :
	sprintf qq(<TR><TD>&nbsp;</TD><TD>&nbsp;</TD><TD>&nbsp;</TD><TD align="center"><A href="%s">コンテキストの右側でソートする</A></TD></TR>\n), $link4contextR;

    for (my $i = 0; $i < scalar(@$kwics); $i++) {
	my $key = $kwics->[$i]{contextL} . ":" . $kwics->[$i]{rawstring} . ":" . $kwics->[$i]{contextR};
	next if (exists $buf{$key});
	$buf{$key} = 1;

	my $did = $kwics->[$i]{did};
	my $title = $kwics->[$i]{title};
	my $keyword = $kwics->[$i]{keyword};
	my $contextR = join("<FONT color=red>|</FONT>", @{$kwics->[$i]{contextsR}});
	my $contextL = join("<FONT color=red>|</FONT>", @{$kwics->[$i]{contextsL}});

	if ($title eq '') {
	    $title = 'no_title.';
	} else {
	    $title = substr($title, 0, $CONFIG->{MAX_LENGTH_OF_TITLE}) . "..." if (length($title) > $CONFIG->{MAX_LENGTH_OF_TITLE});
	}

	$output .= sprintf qq(<TR><TD style="width: %dem; vertical-align: top;" nowrap>), $CONFIG->{MAX_LENGTH_OF_TITLE} + 2;
	$output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	$output .=  $title . "</a>";
	$output .= "</TD>";

	$output .= "<TD align=right nowrap>$contextL</TD>";
	$output .= qq(<TD align=center style="background-color: yellow;" nowrap>$keyword</TD>);
	$output .= "<TD nowrap>$contextR</TD></TR>\n";
    }
    $output .= qq(<TR><TD colspan="4"><HR style="border-top: 1px solid black;"></TD></TR>\n);
    $output .= "</TABLE></CENTER>";

    print $output;
}


sub printOrdinarySearchResult {
    my ($this, $logger, $params, $results, $query, $start, $end, $did2snippets) = @_;

    ################
    # 検索結果を表示
    ################
    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);
    for (my $rank = $start; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $results->[$rank]{did});
	my $score = $results->[$rank]{score_total};
	my $snippet = $did2snippets->{$did};
	my $title = $results->[$rank]{title};

	$score = sprintf("%.4f", $score);

	my $output = qq(<DIV class="result">);

	$output .= qq(<TABLE cellpadding="0" border="0" width="100%"><TR><TD>\n);
	$output .= qq(<SPAN class="rank">) . ($rank + 1) . "</SPAN>";
	$output .= qq(</TD>\n);

	$output .= qq(<TD>\n);
	$output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	$output .= $title . "</a>";

	if ($params->{from_portal}) {
	    $output .= qq(<SPAN style="color: white">id=$did, score=$score</SPAN>\n);
	}
	$output .= qq(</TD></TR>\n);

	$output .= qq(<TR><TD>&nbsp</TD>\n);

	$output .= qq(<TD>\n);
	my $num_of_sim_pages = 0;
	$num_of_sim_pages = scalar(@{$results->[$rank]{similar_pages}}) if (defined $results->[$rank]{similar_pages});

	if (defined $num_of_sim_pages && $num_of_sim_pages > 0) {
	    my $open_label = "類似ページを表示 ($num_of_sim_pages 件)";
	    my $close_label = "類似ページを非表示 ($num_of_sim_pages 件)";
	    if ($params->{from_portal}) {
		$output .= qq(<DIV class="meta"><A href="javascript:void(0);" onclick="toggle_simpage_view('simpages_$rank', this, '$open_label', '$close_label');">$open_label</A> </DIV>\n);
	    } else {
		if ($params->{score_verbose}) {
		    $output .= sprintf qq(<DIV class="meta">id=%09d, score=%.3f (w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f), <A href="javascript:void(0);" onclick="toggle_simpage_view('simpages_$rank', this, '%s', '%s');">%s</A></DIV>\n), $did, $score, $results->[$rank]{score_word}, $results->[$rank]{score_dpnd}, $results->[$rank]{score_dist}, $results->[$rank]{score_word_anchor},$results->[$rank]{score_dpnd_anchor}, $open_label, $close_label;
		} else {
		    $output .= qq(<DIV class="meta">id=$did, score=$score, <A href="javascript:void(0);" onclick="toggle_simpage_view('simpages_$rank', this, '$open_label', '$close_label');">$open_label</A></DIV>\n);
		}
	    }
	} else {
	    unless ($params->{from_portal}) {
		$output .= sprintf qq(<DIV class="meta">id=%09d, score=%.3f (w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f)</DIV>\n), $did, $score, $results->[$rank]{score_word}, $results->[$rank]{score_dpnd}, $results->[$rank]{score_dist}, $results->[$rank]{score_word_anchor}, $results->[$rank]{score_dpnd_anchor};
		# $output .= qq(<DIV class="meta">id=$did, score=$score</DIV>\n)
	    }
	}
	$output .= qq(<BLOCKQUOTE class="snippet">$snippet</BLOCKQUOTE>);
	$output .= qq(<A class="cache" href="$results->[$rank]{url}" target="_blank">$results->[$rank]{url}</A>\n);
	$output .= "</DIV>";

	$output .= qq(<DIV id="simpages_$rank" style="display: none;">);
	foreach my $sim_page (@{$results->[$rank]{similar_pages}}) {
	    my $did = sprintf("%09d", $sim_page->{did});
	    my $score = $sim_page->{score_total};

	    # 装飾されたスニペッツの取得
	    my $snippet = $did2snippets->{$did};
	    $score = sprintf("%.4f", $score);

	    $output .= qq(<DIV class="similar">);
	    $output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	    $output .= $sim_page->{title} . "</a>";
	    if ($params->{from_portal}) {
		$output .= qq(<SPAN style="color: white">id=$did, score=$score</SPAN><BR>\n);
	    } else {
		$output .= qq(<DIV class="meta">id=$did, score=$score</DIV>\n);
	    }
	    # $output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
	    $output .= "<A class=\"cache\" href=\"$sim_page->{url}\">$sim_page->{url}</A>\n";
	    $output .= "</DIV>";
	}
	$output .= qq(</TD></TR></TABLE>\n);
	$output .= "</DIV>\n";

	# 1 ページ分の結果を表示
	print $output;
    }
}


sub printRequestResult {
    my ($this, $dids, $results, $requestItems, $opt) = @_;
    # 出力
    my $date = `date +%m%d-%H%M%S`; chomp ($date);
    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    $writer->startTag('DocInfo',
		      time => $date,
		      result_items => join(':', sort {$b cmp $a} keys %$requestItems));
    foreach my $did (@$dids) {
	&printResult($writer, $did, $results->{$did}, $opt);
    }
    $writer->endTag('DocInfo');
}


# 検索結果に含まれる１文書を出力
sub printResult {
    my ($writer, $did, $results, $opt) = @_;

    $writer->startTag('Result', Id => sprintf("%09d", $did));
    foreach my $itemName (sort {$b cmp $a} keys %$results) {
	if ($itemName ne 'Cache') {
	    if ($itemName eq 'Snippet' && $opt->{kwic}) {
		my $kwics = $results->{$itemName};

		foreach my $kwic (@$kwics) {
		    $writer->startTag('KWIC');

		    $writer->startTag('Keyword');
		    $writer->characters($kwic->{keyword});
		    $writer->endTag('Keyword');

		    $writer->startTag('LeftContext');
		    $writer->characters($kwic->{contextL});
		    $writer->endTag('LeftContext');

		    $writer->startTag('RightContext');
		    $writer->characters($kwic->{contextR});
		    $writer->endTag('RightContext');

		    $writer->endTag('KWIC');
		}
	    } else {
		$writer->startTag($itemName);
		$writer->characters($results->{$itemName}. "\n");
		$writer->endTag($itemName);
	    }
	} else {
	    $writer->startTag($itemName);
	    $writer->startTag('Url');
	    $writer->characters($results->{Cache}{URL});
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters($results->{Cache}{Size});
	    $writer->endTag('Size');
	    $writer->endTag($itemName);
	}
    }
    $writer->endTag('Result');
}


sub printSearchResultForAPICall {
    my ($this, $params, $result, $query, $from, $end, $hitcount) = @_;

    my $did2snippets = {};
    if ($params->{no_snippets} < 1 || $params->{Snippet} > 0) {
	$did2snippets = $this->get_snippets($params, $result, $query, $from, $end);
    }

    my $queryString;
    if ($params->{query_verbose}) {
	foreach my $qk (@{$query->{keywords}}) {
	    $queryString .= $qk->to_string_simple();
	}
    } else {
 	$queryString = $params->{'query'};
    }

    # current time
    my $timestamp = strftime("%Y-%m-%d %T", localtime(time));

    require XML::Writer;

    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    $writer->startTag('ResultSet', time => $timestamp, query => $queryString,
		      totalResultsAvailable => $hitcount, 
		      totalResultsReturned => $end - $from, 
		      firstResultPosition => $params->{'start'} + 1,
		      logicalOperator => $params->{'logical_operator'},
		      forceDpnd => $params->{'force_dpnd'},
		      dpnd => $params->{'dpnd'},
		      anchor => $params->{flag_of_anchor_use},
		      filterSimpages => $params->{'filter_simpages'},
		      sort_by => $params->{'sort_by'}
	);

    for (my $rank = $from; $rank < $end; $rank++) {
	my $page = $result->[$rank];
	my $did = sprintf("%09d", $page->{did});
	my $url = $page->{url};
	my $score = $page->{score_total};
	my $title = $page->{title};
	my $cache_location = $page->{cache_location};
	my $cache_size = $page->{cache_size};

	if ($params->{Score} > 0) {
	    if ($params->{Id} > 0) {
		$writer->startTag('Result', Rank => $rank + 1, Id => $did, Score => sprintf("%.5f", $score));
	    } else {
		$writer->startTag('Result', Rank => $rank + 1, Score => sprintf("%.5f", $score));
	    }
	} else {
	    if ($params->{Id} > 0) {
		$writer->startTag('Result', Rank => $rank + 1, Id => $did);
	    } else {
		$writer->startTag('Result', Rank => $rank + 1);
	    }
	}

	if ($params->{Title} > 0) {
	    $writer->startTag('Title');

	    $title =~ s/\x09//g;
	    $title =~ s/\x0a//g;
	    $title =~ s/\x0b//g;
	    $title =~ s/\x0c//g;
	    $title =~ s/\x0d//g;

	    $writer->characters($title);
	    $writer->endTag('Title');
	}

	if ($params->{Url} > 0) {
	    $writer->startTag('Url');
	    $writer->characters($url);
	    $writer->endTag('Url');
	}

	if ($params->{Snippet} > 0) {
	    if ($params->{kwic}) {
		foreach my $kwic (@{$did2snippets->{$did}}) {
		    $writer->startTag('KWIC');

		    $writer->startTag('Keyword');
		    $writer->characters($kwic->{keyword});
		    $writer->endTag('Keyword');

		    $writer->startTag('LeftContext');
		    $writer->characters($kwic->{contextL});
		    $writer->endTag('LeftContext');

		    $writer->startTag('RightContext');
		    $writer->characters($kwic->{contextR});
		    $writer->endTag('RightContext');

		    $writer->endTag('KWIC');
		}
	    } else {
		$writer->startTag('Snippet');
		$writer->characters($did2snippets->{$did});
		$writer->endTag('Snippet');
	    }
	}

	if ($params->{Cache} > 0) {
	    $writer->startTag('Cache');
	    $writer->startTag('Url');
	    $writer->characters($cache_location);
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters($cache_size);
	    $writer->endTag('Size');
	    $writer->endTag('Cache');
	}

	$writer->endTag('Result');
    }
    $writer->endTag('ResultSet');
    $writer->end();
}

# クラスメソッド
sub printErrorMessage {
    my ($cgi, $msg) = @_;

    print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
    print $msg . "\n";
}

1;
