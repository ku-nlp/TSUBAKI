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

    if (defined $this->{SYNONYM_DB}) {
	untie %$this->{SYNONYM_DB};
    }
}

sub printQuery {
    my ($this, $logger, $params, $size, $query, $status) = @_;

    if ($status eq 'busy') {
	printf qq(<DIV style="text-align: center; color: red;">ただいま検索サーバーが混雑しています。時間をおいてから再検索して下さい。</DIV>);
	return;
    }

    $this->{q2color} = $this->print_query($query);

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
    print qq(<A href="javascript:void(0);" style="color:white; text-decoration: none;" onclick="toggle_simpage_view('slave_server_logs', this, '.', '.');">.</A>\n);
    print "</TD></TR></TABLE>\n";
}

sub printFooter {
    my ($this, $params, $hitcount, $current_page, $size, $opt) = @_;

    if ($opt->{kwic}) {
	print "<P>\n";
    } else {
	my $last_page_flag = 0;
	if ($hitcount > $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}) {
	    print "<DIV class='pagenavi'>検索結果ページ：";
	    my $num_of_search_results = ($CONFIG->{'NUM_OF_SEARCH_RESULTS'} > $CONFIG->{'NUM_OF_PROVIDE_SEARCH_RESULTS'}) ? $CONFIG->{'NUM_OF_PROVIDE_SEARCH_RESULTS'} : $CONFIG->{'NUM_OF_SEARCH_RESULTS'};
	    for (my $i = 0; $i < $num_of_search_results / $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}; $i++) {
		my $offset = $i * $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'} + 1;
		if ($size < $offset) {
		    last;
		} else {
		    $last_page_flag = 0;
		}

		if ($offset - 1 == $current_page) {
		    print "<font color=\"brown\">" . ($i + 1) . "</font>&nbsp;";
		    $last_page_flag = 1;
		} else {
 		    if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
			my @buf;
			foreach my $tag (keys %{$CONFIG->{BLOCK_TYPE_DATA}}) {
			    if ($CONFIG->{BLOCK_TYPE_DATA}{$tag}{isChecked}) {
				push (@buf, sprintf ("blockTypes=%s", $tag));
			    }
			}
			printf qq(<a href="index.cgi?start=%d&query=%s&%s">%d</a>&nbsp;), $offset, $params->{query}, join ("&", @buf), $i + 1;
 		    } else {
			printf qq(<a href="index.cgi?start=%d&query=%s">%d</a>&nbsp;), $offset, $params->{query}, $i + 1;
		    }
		}
	    }
	    print "</DIV>";
	}
	printf("<DIV class=\"bottom_message\">上の%d件と類似・関連したページは除外されています。</DIV>\n", $size) if ($last_page_flag && $size < $hitcount && $size < $CONFIG->{'NUM_OF_SEARCH_RESULTS'});
    }


    # フッタ出力
    print << "END_OF_HTML";

    <DIV style="text-align:center;padding:1em;">
    TSUBAKI利用時の良かった点、問題点などご意見を頂けると幸いです。<br>
    ご意見は tsubaki-feedback あっと nlp.kuee.kyoto-u.ac.jp までお願い致します。
    <P>
    <DIV><B>&copy;2006 - 2009 黒橋研究室</B></DIV> 
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
    my($this, $query) = @_;

    print qq(<TABLE width="100%" border="0" class="querynavi"><TR><TD width="*" style="padding: 0.25em 1em; background-color:#f1f4ff;">\n);
    if (scalar(@{$query->{keywords}}) > 0) {
	my @buf;
	for (my $i = 0; $i < scalar(@{$query->{keywords}}); $i++) {
	    my $kwd = $query->{keywords}[$i];
	    push(@buf, sprintf (qq(<A href="#" style="font-weight: 900;" id="query%d">%s</A>), $i, $kwd->{rawstring}));
	}
	print join('&nbsp;', @buf);
    } else {
	printf ("site:%s", $query->{option}{site});
    }
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

sub printJavascriptCode {
    my ($canvasName, $query) = @_;

    print << "END_OF_HTML";
    <script language="JavaScript">
	var regexp = new RegExp("Gecko");
    if (navigator.userAgent.match(regexp)) {
	document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.gecko.css'>");
    } else {
	document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.ie.css'>");
    }

    </script>
    <script type="text/javascript" src="http://reed.kuee.kyoto-u.ac.jp/~skeiji/wz_jsgraphics.js"></script>
    <script type="text/javascript" src="http://reed.kuee.kyoto-u.ac.jp/~skeiji/prototype.js"></script>
    <script type="text/javascript" src="http://reed.kuee.kyoto-u.ac.jp/~skeiji/tsubaki.js"></script>

    <script language="JavaScript">
END_OF_HTML

print "var jg;\n";
    print "function init () {\n";
    print "jg = new jsGraphics($canvasName);\n";

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
    print "</script>\n";
}

sub print_tsubaki_interface {
    my ($this, $params, $query, $status) = @_;

    my $canvasName = 'canvas';
    my $title = "情報爆発プロジェクト 検索エンジン基盤 TSUBAKI";
    $title .= " (情報処理学会 論文検索版)" if ($CONFIG->{IS_IPSJ_MODE});

    print << "END_OF_HTML";
    <html>
	<head>
	<title>$title</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="css/tsubaki.common.css">
END_OF_HTML
    my ($width, $height, $jscode) = $query->{keywords}[0]->getPaintingJavaScriptCode() if (defined $query->{keywords}[0]);
    &printJavascriptCode('canvas', $query);
    print << "END_OF_HTML";
    </head>
	<body style="padding: 0em; margin:0em; z-index:1;" onload="javascript:init();">
	  <TABLE cellpadding="0" cellspacing="0" border="0" id="baroon" style="display: none; z-index: 10; position: absolute; top: 100; left: 100;">
	    <TR>
	      <TD><IMG width="24" height="24" src="image/curve-top-left.png"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD><IMG width="24" height="24" src="image/curve-top-right.png"></TD>
	    </TR>
	    <TR>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD style="background-color:#ffffcc;" id="canvas"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	    </TR>
	    <TR>
	      <TD><IMG width="24" height="24" src="image/curve-bottom-left.png"></TD>
	      <TD style="background-color:#ffffcc;"></TD>
	      <TD><IMG width="24" height="24" src="image/curve-bottom-right.png"></TD>
	    </TR>
	  </TABLE>
END_OF_HTML

    my $host = `hostname`;
    print qq(<DIV style="font-size:smaller; width: 100%; text-align: right; padding:0em 0em 0em 0em;">\n);
    # print qq(<A href="http://www.infoplosion.nii.ac.jp/info-plosion/index.php"><IMG border="0" src="image/info-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html"><IMG style="padding: 0.5em 0em;" border="0" src="image/tutorial-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/whats.html">[おしらせ等]</A>\n); 
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html">[お知らせ・使い方]</A><BR>\n);

    # 混雑具合を表示
    if ($CONFIG->{DISPLAY_CONGESTION}) {
	my ($count, $foregroundColor, $backgroundColor) = &getCongestion();
	print qq(<SPAN style="color: $foregroundColor; background-color: $backgroundColor;">&nbsp;混具合:&nbsp;$count クエリ/分</SPAN>);
    }
    print qq(</DIV>\n);

    # タイトル出力
    print qq(<TABLE width="100%" border="0"><TR><TD width="220" align="center" valign="middle" style="border: 0px solid red;">\n);
    if ($CONFIG->{IS_IPSJ_MODE}) {
	printf ("<A href=%s><IMG border=0 src=image/logo-mini.png></A><BR>\n", $CONFIG->{INDEX_CGI});
	print qq(<SPAN style="color:#F60000; font-size:x-small; font-weight:bold;">- 情報処理学会 論文検索版 -</SPAN></TD>\n);
    } else {
	printf ("<A href=%s><IMG border=0 src=image/logo-mini.png></A></TD>\n", $CONFIG->{INDEX_CGI});
    }

    # フォーム出力
    print qq(<TD width="*" align="left" valign="middle" style="border: 0px solid red; padding-top: 1em;">\n);
    print qq(<FORM name="search" method="GET" action="" enctype="multipart/form-data">\n);
    print qq(<INPUT type="hidden" name="start" value="1">\n);
    print qq(<INPUT type="text" id=\"qbox\" name="query" value="$params->{'query'}" size="60">\n);
    print qq(<INPUT type="submit" value="検索する"/>\n);
    print qq(<INPUT type="button" value="クリア" onclick="document.all.query.value=''"/>\n);


    # 検索に利用するブロックタイプを選択するチェックボックスを表示
    &printBlockTypeCheckbox();


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
	    print "<LABEL><INPUT type=\"checkbox\" name=\"disable_synnode\" disabled></INPUT><FONT color=silver>同義表現を考慮しない</FONT></LABEL>";
	} else {
	    if ($params->{disable_synnode}) {
		print "<LABEL><INPUT type=\"checkbox\" name=\"disable_synnode\" checked></INPUT><FONT color=black>同義表現を考慮しない</FONT></LABEL>";
	    } else {
		print "<INPUT type=\"checkbox\" name=\"disable_synnode\"></INPUT><LABEL><FONT color=black>同義表現を考慮しない</FONT></LABEL>";
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
    print qq(</TD>\n);

    if ($CONFIG->{QUESTIONNAIRE} && $status ne 'busy') {
	print qq(<TD id="questionnairePane" align="right" style="padding-right:0.5em;">\n);
	print qq(<FORM name="questionnarieForm" onsubmit="javascript:send_questionnarie();">);

	print qq(<TABLE id="questionnaire" border="0"><TR><TD nowrap style="color: red; font-weight: bold; padding-bottom:0.3em;">アンケートにご協力下さい。</TD>);
	print qq(<TD align="right"><INPUT type="button" value="送信" style="margin-left: 1em;" onClick="javascript:send_questionnarie();"></TD></TR>);
	print qq(<TR><TD nowrap>);

	print qq(・質問に対して良い検索結果ですか？</TD><TD align="right">);
	print qq(<LABEL><INPUT type="radio" name="question" value="1">YES</LABEL>);
	print qq(<LABEL><INPUT type="radio" name="question" value="0">NO</LABEL></TD></TR>);

	print qq(<TR><TD colspan="2">);
	print qq(・自由記述　);
	print qq(<INPUT size="42" id="message" type="text">);
	print qq(</TD></TR></TABLE>);

	print qq(</FORM>);
	print qq(</TD>\n);
    }

    print qq(</TR></TABLE>\n);

    print "<CENTER>\n";
    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});
    print "</CENTER>\n";
}

sub print_tsubaki_interface_init {
    my ($this, $params) = @_;
    my $title = "情報爆発プロジェクト 検索エンジン基盤 TSUBAKI";
    $title .= " (情報処理学会 論文検索版)" if ($CONFIG->{IS_IPSJ_MODE});
    print << "END_OF_HTML";
    <html>
	<head>
	<title>$title</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="css/tsubaki.common.css">
	<script language="JavaScript">
	var regexp = new RegExp("Gecko");
    if (navigator.userAgent.match(regexp)) {
	document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.gecko.css'>");
    } else {
	document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.ie.css'>");
    }
	</script>
	<script type="text/javascript" src="javascript/tsubaki.js"></script>
	</head>
	<body style="margin:0em; padding:0em;">
END_OF_HTML

my $host = `hostname`;
#    print "TSUBAKI on $host<BR>\n";
    # タイトル出力
    print qq(<DIV style="font-size:smaller; text-align:right;margin:0.5em 1em 0em 0em;">\n);
    # print qq(<A href="http://www.infoplosion.nii.ac.jp/info-plosion/index.php"><IMG border="0" src="image/info-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html"><IMG style="padding: 0.5em 0em;" border="0" src="image/tutorial-logo.png"></A><BR>\n);
    # print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/whats.html">[おしらせ等]</A>\n); 
    print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/tutorial.html">[お知らせ・使い方]</A><BR>\n);

    # 混雑具合を表示
    if ($CONFIG->{DISPLAY_CONGESTION}) {
	my ($count, $foregroundColor, $backgroundColor) = &getCongestion();
	print qq(<SPAN style="color: $foregroundColor; background-color: $backgroundColor;">&nbsp;混具合:&nbsp;$count クエリ/分</SPAN>);
    }
    print qq(</DIV>\n);

    print qq(<CENTER style="maring:1em; padding:1em;">\n);
    printf ("<A href=%s><IMG border=0 src=image/logo.png></A><BR>\n", $CONFIG->{INDEX_CGI});
    print qq(<SPAN style="color:#F60000; font-size:x-small; font-weight:bold;">- 情報処理学会 論文検索版 -</SPAN>\n) if ($CONFIG->{IS_IPSJ_MODE});
    print "<P>\n";

    # フォーム出力
    print qq(<FORM name="search" method="GET" action="$CONFIG->{INDEX_CGI}">\n);
    print "<INPUT type=\"hidden\" name=\"start\" value=\"1\">\n";
    print "<INPUT type=\"text\" id=\"qbox\" name=\"query\" value=\'$params->{'query'}\' size=\"90\">\n";
    print qq(<INPUT type="submit" value="検索する"/>\n);
    print qq(<INPUT type="button" value="クリア" onclick="document.all.query.value=''"/>\n);

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
	    print "<LABEL><INPUT type=\"checkbox\" name=\"disable_synnode\" disabled></INPUT><FONT color=silver>同義表現を考慮しない</FONT></LABEL>";
	} else {
	    if ($params->{disable_synnode}) {
		print "<LABEL><INPUT type=\"checkbox\" name=\"disable_synnode\" checked></INPUT><FONT color=black>同義表現を考慮しない</FONT></LABEL>";
	    } else {
		print "<INPUT type=\"checkbox\" name=\"disable_synnode\"></INPUT><LABEL><FONT color=black>同義表現を考慮しない</FONT></LABEL>";
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

    # 検索に利用するブロックタイプを選択するチェックボックスを表示
    &printBlockTypeCheckbox();

    print "</FORM>\n";

    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});

    print "</CENTER>";

    # フッターの表示
    $this->printFooter($params, 0, 0, 0);
}

sub printBlockTypeCheckbox {
    if ($CONFIG->{USE_OF_BLOCK_TYPES} && !$CONFIG->{DISABLE_BLOCK_TYPE_DISPLAY}) {
	print qq(<TR>\n);
	print qq(<TD colspan=2>\n);
	print qq(<DIV style="padding-top:1em; border: 0px solid green;">\n);
	foreach my $key (@{$CONFIG->{BLOCK_TYPE_KEYS}}) {
	    my $tag = $CONFIG->{BLOCK_TYPE_DATA}{$key}{tag};
	    my $label = $CONFIG->{BLOCK_TYPE_DATA}{$key}{label};
	    my $flag = ($CONFIG->{BLOCK_TYPE_DATA}{$key}{isChecked}) ? 'checked' : '';
	    printf qq(<INPUT name="blockTypes" type="checkbox" value="%s" id="%s" %s/><LABEL for="%s">%s</LABEL>\n), $tag, $tag, $flag, $tag, $label;
	}
	print qq(</DIV>);
    }
}


sub getCongestion {
    my $logfile = $CONFIG->{DATA_DIR} . "/access_log";
    my $count = 1;

    open(READER, "cat $logfile | tac |");
    my $buf = undef;
    while (<READER>) {
	my @data = split(' ', $_);
	my ($date, $hour, $min, $sec) = split(":", $data[3]);
	$buf = 60 + $min unless (defined $buf);

	my $request = $data[6];

	next if ($request !~/cgi/);
	next if ($request =~/cache/);
	next if ($request =~/format=/);
	next if ($request !~/query=/);

	last if (($buf - $min) % 60 > 1);
	if ($request !~ /format/) {
	    $count++;
	}
    }
    close (READER);


    my $backgroundColor = 'red';
    my $foregroundColor = 'yellow';
    if (9 < $count && $count < 20) {
	$backgroundColor = 'orange';
	$foregroundColor = 'black';
    }
    elsif (5 < $count && $count <= 9) {
	$backgroundColor = 'yellow';
	$foregroundColor = 'black';
    }
    elsif (2 < $count && $count <= 5) {
	$backgroundColor = '#CCFF99';
	$foregroundColor = 'black';
    }
    elsif ($count <= 2) {
	$backgroundColor = '#99FFFF';
	$foregroundColor = 'black';
    }


    return ($count, $foregroundColor, $backgroundColor);
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
		my $string = $rep->{midasi_with_yomi};

		# next if ($string =~ /s\d+:/);

		# $string =~ s/s\d+://; # SynID の削除
		# $string =~ s/\/.+$//; # 読みがなの削除

		next if ($string =~ /<^>]+?>/);
		next if (exists $buf1{$string});

		if ($rep->{katsuyou} =~ /ナノ?形容詞/) {
		    my ($hyouki, $yomi) = split ("/", $string);
		    $hyouki =~ s/だ$//;
		    $yomi =~ s/だa?$//;
		    $string = sprintf ("%s/%s", $hyouki, $yomi);
		}

		$buf1{$string}++;
		last;
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

    my @docs = ();
    # スニペット生成のため、類似ページも含め、表示されるページのIDを取得
    for (my $rank = $from; $rank < $end; $rank++) {
	push(@docs, {
# 	    did => sprintf("%09d", $result->[$rank]{did}),
 	    did => $result->[$rank]{did},
 	    start => $result->[$rank]{start},
 	    end => $result->[$rank]{end},
 	    pos2qid => $result->[$rank]{pos2qid}
	     });

#	unless ($this->{called_from_API}) {
#	    foreach my $sim_page (@{$result->[$rank]{similar_pages}}) {
#		push(@dids, sprintf("%09d", $sim_page->{did}));
#	    }
#	}
    }

    my $sni_obj = new SnippetMakerAgent();
    $sni_obj->create_snippets($query, \@docs, { discard_title => 1,
						syngraph => $opt->{'syngraph'},
						# options for snippet creation
						window_size => 5,
						lightweight => 1,
						extract_from_abstract_only => 0,

						# options for kwic
						kwic => $opt->{kwic},
						kwic_window_size => $opt->{kwic_window_size},
						use_of_repname_for_kwic => $opt->{use_of_repname_for_kwic},
						use_of_katuyou_for_kwic => $opt->{use_of_katuyou_for_kwic},
						use_of_dpnd_for_kwic => $opt->{use_of_dpnd_for_kwic},
						use_of_huzokugo_for_kwic => $opt->{use_of_huzokugo_for_kwic},
						use_of_negation_for_kwic => $opt->{use_of_negation_for_kwic},
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


sub printSlaveServerLogs {
    my ($this, $logger) = @_;

    my @keys = ('id', 'port', 'total_time', 'transfer_time_to', 'normal_search', 'index_access', 'merge_synonyms', 'logical_condition', 'near_condition', 'merge_dids', 'document_scoring', 'transfer_time_from', 'hitcount', 'data_size');
    my $host2log = $logger->getParameter('host2log');
    my %buf = ();
    my %average = ();
    my $count = 0;

    my $verboseLogString;
    $verboseLogString .= sprintf qq(<H3 style="border-bottom: 2px solid black;">Verbose</H3>\n);

    foreach my $host (sort keys %$host2log) {
	$verboseLogString .= sprintf qq(<TABLE width="100%">\n);
	$verboseLogString .= sprintf qq(<TR><TD colspan="%d" align="center" style="color: white; font-weight: bold; background-color:gray;">$host</TD></TR>\n), scalar(@keys);
	foreach my $k (@keys) {
	    $verboseLogString .= sprintf qq(<TD align="center" style="color: gray; font-weight: bold; background-color:silver;">$k</TD>);
	}
	$verboseLogString .= sprintf "</TR>\n";

	my $localLoggers = $host2log->{$host};
	foreach my $localLogger (sort {$a->getParameter('port') <=> $b->getParameter('port')} @$localLoggers) {
	    # printf qq(<H3 style="border-bottom: 2px solid black;">%s (%s)</H3>\n), $host, $localLogger->getParameter('port');
	    # print $localLogger->toHTMLCodeOfAccessTimeOfIndex();

	    my $cells;
	    foreach my $k (@keys) {
		my $v = ($localLogger) ? $localLogger->getParameter($k) : '---';
		$cells .= sprintf qq(<TD align="right" style="background-color: white;">$v</TD>);
		$average{$k} += $v if ($localLogger);
	    }
	    $verboseLogString .= sprintf "<TR>$cells</TR>";
	    $buf{qq(<TD align="center" style="background-color: white;">$host</TD>) . $cells} = ($localLogger) ? $localLogger->getParameter('total_time') : '---';
	    $count++;
	}
	$verboseLogString .= sprintf "</TABLE>\n";
    }


    my @buff = ();
    foreach my $host (sort keys %$host2log) {
	my $localLoggers = $host2log->{$host};
	foreach my $localLogger (sort {$a->getParameter('port') <=> $b->getParameter('port')} @$localLoggers) {
	    my $buf = {host => $host};
	    foreach my $k (@keys) {
		next unless ($k eq 'id' || $k eq 'port' || $k eq 'hitcount');
		$buf->{$k} = ($localLogger) ? $localLogger->getParameter($k) : '---';
	    }

	    # print Dumper::dump_as_HTML($localLogger) . "\n";
	    # print "<HR>\n";

	    push (@buff, $buf);
	}
    }

    $verboseLogString .= sprintf qq(<H3 style="border-bottom: 2px solid black;">Table of ID and hitcount</H3>\n);
    $verboseLogString .= "<TABLE border=1>\n";
    $verboseLogString .= sprintf "<TR><TD>%s</TD><TD>%s</TD><TD>%s</TD><TD>%s</TD></TR>", 'hostname', 'id', 'port', 'hitcount';
    foreach my $i (sort {$a->{id} <=> $b->{id}} @buff) {
	$verboseLogString .= "<TR>\n";
	$verboseLogString .= sprintf "<TD>%s</TD>", $i->{host};
	foreach my $k (@keys) {
	    next unless (exists $i->{$k});
	    $verboseLogString .= sprintf "<TD>%s</TD>", $i->{$k};
	}
	$verboseLogString .= "</TR>\n";
    }
    $verboseLogString .= "</TABLE>\n";


    print qq(<DIV id="slave_server_logs" style="padding: 0em 1em 2em 1em; display: none; background-color: #f1f4ff;">);
    print qq(<DIV>[<A href="javascript:void(0);" onclick="toggle_simpage_view('slave_server_log_verbose', this, '詳細を開く', '詳細を閉じる');">詳細を開く</A>]&nbsp;\n);
    print qq([<A href="javascript:void(0);" onclick="javascript:document.getElementById('slave_server_logs').style.display = 'none';">ログを閉じる</A>]</DIV>\n);

    # クエリの解析時間のログ
    my @keysForQueryParsetime = ('parse_query', 'new_syngraph', 'KNP', 'QueryAnalyzer', 'SynGraph', 'Indexer', 'create_query', 'set_params_for_qks');
    printf qq(<H3 style="border-bottom: 2px solid black;">Query Parse Time</H3>\n);
    printf qq(<TABLE width="100%">\n<TR>);
    foreach my $k (@keysForQueryParsetime) {
	my $kk = ($k eq 'parse_query') ? 'total_time' : $k;
	printf qq(<TD align="center" style="color: white; font-weight: bold; background-color:gray;">$kk</TD>);
    }
    printf "</TR>\n";

    foreach my $k (@keysForQueryParsetime) {
	printf qq(<TD align="center" style="color:black; background-color:white;">%s</TD>), $logger->getParameter($k);
    }
    printf "</TR>\n</TABLE>\n";



    print qq(<H3 style="border-bottom: 2px solid black;">Summary of Search Time</H3>\n);
    print qq(<TABLE width="100%">\n);
    printf qq(<TR><TD colspan="%d" align="center" style="color: white; font-weight: bold; background-color:gray;">AVERAGE</TD></TR>\n), scalar(@keys);
    foreach my $k (@keys) {
	next if ($k eq 'port' || $k eq 'id');
	print qq(<TD align="center" style="color: gray; font-weight: bold; background-color:silver;">$k</TD>);
    }
    print "</TR>\n";
    foreach my $k (@keys) {
	next if ($k eq 'port' || $k eq 'id');
	my $v = ($count > 0) ? sprintf ("%.3f", ($average{$k} / $count)) : -1;
	print qq(<TD align="right" style="background-color: white;">$v</TD>);
    }
    print "</TABLE>\n";


    my $rank = 1;
    my $N = 20;
    print qq(<TABLE width="100%">\n);
    unshift (@keys, 'host');
    printf qq(<TR><TD colspan="%d" align="center" style="color: white; font-weight: bold; background-color:gray;">WORST $N</TD></TR>\n), scalar(@keys);
    foreach my $k (@keys) {
	print qq(<TD align="center" style="color: gray; font-weight: bold; background-color:silver;">$k</TD>);
    }
    print "</TR>\n";
    foreach my $cells (sort {$buf{$b} <=> $buf{$a}} keys %buf) {
	print "<TR>$cells</TR>\n";
	last if (++$rank > $N);
    }
    print "</TABLE>\n";

    print qq(<DIV id="slave_server_log_verbose" style="display:none;">$verboseLogString</DIV>);
    print "</DIV>\n";
}


sub printSearchResultForBrowserAccess {
    my ($this, $params, $results, $query, $logger, $status) = @_;

    ##################################
    # 検索スレーブサーバーのログを表示
    ##################################
    $this->printSlaveServerLogs($logger) unless ($logger->getParameter('IS_CACHE'));


    ##########################
    # ロゴ、検索フォームの表示
    ##########################
    $this->print_tsubaki_interface($params, $query, $status);


    my $size = scalar(@$results);
    my $start = $params->{start};
    my $end = ($start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE} > $size) ? $size : $start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE};


    ##################
    # 検索クエリの表示
    ##################
    $this->printQuery($logger, $params, $size, $query, $status);


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


    ############################################
    # KWIC or 論文検索 or 通常版の検索結果を表示
    ############################################
    ($params->{kwic}) ? $this->printKwicView($params, $results, $query) :
	(($CONFIG->{IS_IPSJ_MODE}) ? $this->printIPSJSearchResult($logger, $params, $results, $query, $start, $end, $did2snippets) : $this->printOrdinarySearchResult($logger, $params, $results, $query, $start, $end, $did2snippets));

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
#	my $did = sprintf("%09d", $results->[$rank]{did});
	my $did = $results->[$rank]{did};
	my $score = sprintf("%.4f", $results->[$rank]{score_total});
	my $snippet = $did2snippets->{$did};
	my $title = $results->[$rank]{title};

	my $output = qq(<DIV class="result">);

	###############################################################################
	# 順位とタイトル
	###############################################################################

	$output .= qq(<TABLE cellpadding="0" border="0" width="100%">\n);
	$output .= qq(<TR><TD style="width: 1em; text-align: center;"><SPAN class="rank" nowrap>) . ($rank + 1) . "</SPAN></TD>\n";

	$output .= qq(<TD>\n);
	$output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	$title = substr($title, 0, $CONFIG->{MAX_LENGTH_OF_TITLE}) . "..." if (length($title) > $CONFIG->{MAX_LENGTH_OF_TITLE});
	$output .= $title . "</a>";

	if ($params->{from_portal}) {
	    $output .= qq(<SPAN style="color: white">id=$did, score=$score</SPAN>\n);
	}

	$output .= qq(</TD></TR>\n);
	$output .= qq(<TR><TD>&nbsp</TD>\n);
	$output .= qq(<TD>\n);


	###############################################################################
	# タイトルの下
	###############################################################################

	$output .= qq(<DIV class="meta">\n);
	# ポータルからのアクセスでなければ文書IDとスコアを表示する
	if (!$params->{from_portal}) {
#	    $output .= sprintf qq(id=%09d, score=%.3f), $did, $score;
	    $output .= sprintf qq(id=%s, score=%.3f), $did, $score;
	}

	# score_verbose が指定去れている場合は内訳を表示する
	if ($params->{score_verbose}) {
	    my $score_w = $results->[$rank]{score_word};
	    my $score_d = $results->[$rank]{score_dpnd};
	    my $score_n = $results->[$rank]{score_dist};
	    my $score_aw = $results->[$rank]{score_word_anchor};
	    my $score_dw = $results->[$rank]{score_dpnd_anchor};
	    my $score_pr = $results->[$rank]{pagerank};
	    if ($CONFIG->{DISABLE_PAGERANK}) {
		$output .= sprintf qq((w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f)), $score_w, $score_d, $score_n, $score_aw, $score_dw;
	    } else {
		$output .= sprintf qq((w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f, pr=%s)), $score_w, $score_d, $score_n, $score_aw, $score_dw, $score_pr;
	    }
	}

	# 類似・関連ページがあれば表示する
	my $num_of_sim_pages = (defined $results->[$rank]{similar_pages}) ? scalar(@{$results->[$rank]{similar_pages}}) : 0;
	if (defined $num_of_sim_pages && $num_of_sim_pages > 0) {
	    my $open_label = "類似・関連ページを表示 ($num_of_sim_pages 件)";
	    my $close_label = "類似・関連ページを非表示 ($num_of_sim_pages 件)";
	    $output .= sprintf qq(&nbsp;<A href="javascript:void(0);" onclick="toggle_simpage_view('simpages_$rank', this, '%s', '%s');">%s</A>\n), $open_label, $close_label, $open_label;
	}
	$output .= qq(</DIV>\n);


	###############################################################################
	# スニペット
	###############################################################################

	$output .= qq(<BLOCKQUOTE class="snippet">$snippet</BLOCKQUOTE>);
	$output .= qq(<A class="cache" href="$results->[$rank]{url}" target="_blank">$results->[$rank]{url}</A>\n);

	if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
	    # ページの構造解析結果へのリンクを生成
	    my $block_type_detect_url = sprintf "http://orchid.kuee.kyoto-u.ac.jp/~funayama/ISA/index_dev.cgi?DetectBlocks_ROOT=%%2Fhome%%2Ffunayama%%2Fcvs%%2FDetectBlocks&DetectSender_ROOT=%%2Fhome%%2Ffunayama%%2Fcvs%%2FDetectSender&inputurl=%s?format=html\@id=%s&DetectSender_flag=&rel2abs=", "http://tsubaki.ixnlp.nii.ac.jp/api.cgi", $did;
	    $output .= qq(&nbsp;<A class="cache" href="$block_type_detect_url" target="_blank"><SMALL>構造解析結果</SMALL></A>\n);
	}
	$output .= "</DIV>";


	###############################################################################
	# 類似・関連ページ
	###############################################################################

	$output .= qq(<DIV id="simpages_$rank" style="display: none;">);
	foreach my $sim_page (@{$results->[$rank]{similar_pages}}) {
#	    my $did = sprintf("%09d", $sim_page->{did});
	    my $did = $sim_page->{did};
	    my $score = sprintf("%.3f", $sim_page->{score_total});

	    # 装飾されたスニペッツの取得
	    my $snippet = $did2snippets->{$did};

	    $output .= qq(<DIV class="similar">);
	    $output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	    $output .= $sim_page->{title} . "</a>";
	    if ($params->{from_portal}) {
		# $output .= qq(<SPAN style="color: white">id=$did, score=$score</SPAN><BR>\n);
		$output .= qq(<BR>\n);
	    } else {
		$output .= qq(<DIV class="meta">id=$did, score=$score);
		# score_verbose が指定去れている場合は内訳を表示する
		if ($params->{score_verbose}) {
		    my $score_w = $results->[$rank]{score_word};
		    my $score_d = $results->[$rank]{score_dpnd};
		    my $score_n = $results->[$rank]{score_dist};
		    my $score_aw = $results->[$rank]{score_word_anchor};
		    my $score_dw = $results->[$rank]{score_dpnd_anchor};
		    $output .= sprintf qq((w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f)), $score_w, $score_d, $score_n, $score_aw, $score_dw;
		}
		$output .= "</DIV>\n";
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

sub printIPSJSearchResult {
    my ($this, $logger, $params, $results, $query, $start, $end, $did2snippets) = @_;

    ################
    # 検索結果を表示
    ################
    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);
    for (my $rank = $start; $rank < $end; $rank++) {
	my $did = $results->[$rank]{did};
	my $bibdat = $results->[$rank]{bibdat};
	if ($bibdat) {
	    my ($authors, $booktitle, $voln, $spage, $epage, $year) = split (" ", $bibdat);
 	    my ($volume, $number) = split (",", $voln);
 	    $number =~ s/　//;
	    push (@{$results->[$rank]{authors}}, $authors);
	    $results->[$rank]{booktitle} = $booktitle;
	    $results->[$rank]{volume} = $volume;
	    $results->[$rank]{number} = $number;
	    $results->[$rank]{page} = sprintf qq(%s-%s), $spage, $epage;
	    $results->[$rank]{year} = $year;
	}

	$results->[$rank]{rank} = $rank + 1;
	$results->[$rank]{snippet} = $did2snippets->{$did};

	# 一件分を作成して表示する
	print $this->_printIPSJSearchResult($results->[$rank], $query);
    }
}


sub _printIPSJSearchResult {
    my ($this, $result, $query) = @_;

    ################
    # 検索結果を表示
    ################

    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);
    my $rank = $result->{rank};
    my $did = $result->{did};
    my $score = sprintf("%.4f", $result->{score_total});
    my $snippet = $result->{snippet};
    my $title = $result->{title};
    my $abst = $result->{abst};
    my $abstAll = $result->{abstAll};

    my $output = qq(<DIV class="result">);



    ###############################################################################
    # 順位とタイトル
    ###############################################################################

    $output .= qq(<TABLE cellpadding="0" border="0" width="100%">\n);
    $output .= qq(<TR><TD style="width: 1em; text-align: center; vertical-align: top;"><SPAN class="rank" nowrap>) . ($rank) . "</SPAN></TD>\n";

    $output .= qq(<TD>\n);
    $title = substr($title, 0, $CONFIG->{MAX_LENGTH_OF_TITLE}) . "..." if (length($title) > $CONFIG->{MAX_LENGTH_OF_TITLE});
    if (defined $result->{url}) {
	$output .= qq(<A class="title" href="$result->{url}" target="_blank">$title</A>\n) if (defined $result->{url});
    } else {
	$output .= sprintf qq(<SPAN stype="color; black;">$title</SPAN>\n), $title;
    }
    $output .= qq(<SPAN style="font-size:small;">);
    $output .= sprintf qq(<A href="http://ci.nii.ac.jp/lognavi?name=nels&lang=jp&type=pdf&id=%s" target="_blank">[PDF]</A>&nbsp;&nbsp;\n), $result->{artid} if ($result->{artid});
    $output .= qq(<A href="$CONFIG->{INDEX_CGI}?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">[TXT]</A>&nbsp;&nbsp;\n);
    $output .= qq(<A href="$CONFIG->{INDEX_CGI}?did=$did&type=meta" target="_blank" class="ex">[メタ情報]</A>&nbsp;&nbsp;\n);
    $output .= sprintf qq(<A href="javascript:void($rank);" onclick="toggle_ipsj_verbose_view('test1_$rank', 'test2_$rank', 'test3_$rank', 'test4_$rank', this, '%s', '%s');">[ABST・本文の詳細]</A>\n), "[ABST・本文の詳細]", "[元に戻す]" if ($abstAll);
    $output .= "</SPAN>";

    $output .= qq(</TD></TR>\n);
    $output .= qq(<TR><TD>&nbsp</TD>\n);
    $output .= qq(<TD>\n);

#     my $score_w = $result->{score_word};
#     my $score_d = $result->{score_dpnd};
#     my $score_n = $result->{score_dist};
#     my $score_aw = $result->{score_word_anchor};
#     my $score_dw = $result->{score_dpnd_anchor};
#     my $score_pr = $result->{pagerank};
#     $output .= sprintf qq((w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f)), $score_w, $score_d, $score_n, $score_aw, $score_dw;

    ###############################################################################
    # タイトルの下
    ###############################################################################

    # クエリとマッチした著者名を太字で表示
    my $_authors = "";
    if (defined $result->{authors}) {
	$_authors = join ("，", @{$result->{authors}});
	foreach my $kwd (@{$query->{keywords}}) {
	    foreach my $word (@{$kwd->{words}}) {
		foreach my $w (@{$word}) {
		    $_authors =~ s!\Q$w->{string}\E!<B>$w->{string}</B>!g;
		}
	    }
	}
    }

    $output .= sprintf qq(<BLOCKQUOTE class="bib">%s; %s %s（%s）), $_authors, $result->{booktitle}, $result->{volume}, $result->{number} if ($result->{number});
    $output .= sprintf qq(, %s), $result->{page} if ($result->{page});
    $output .= sprintf qq(, %s年), $result->{year} if ($result->{year} =~ /^\d\d\d\d$/);
    $output .= sprintf qq(</BLOCKQUOTE>\n);


    ###############################################################################
    # スニペット
    ###############################################################################

    my $MAX_LENGTH_OF_SHORT_SNIPPET = 100;
    if ($abstAll) {
	my $short_abst = (defined $abst) ? $abst : $this->makeShortSnippet($abstAll, $MAX_LENGTH_OF_SHORT_SNIPPET);

	$output .= qq(<BLOCKQUOTE id="test1_$rank" style="display: block;" class="snippet"><SPAN style="border: 0px solid black; background-color:maroon; color:white; font-weight:bold; padding:0em 0.5em; margin-right:0.5em;">ABST</SPAN>$short_abst...</BLOCKQUOTE>);
	$output .= qq(<BLOCKQUOTE id="test2_$rank" style="display: none;" class="snippet"><SPAN style="border: 0px solid black; background-color:maroon; color:white; font-weight:bold; padding:0em 0.5em; margin-right:0.5em;">ABST</SPAN>$abstAll</BLOCKQUOTE>);
    }

    my $short_snippet = $this->makeShortSnippet($snippet, $MAX_LENGTH_OF_SHORT_SNIPPET);
    $short_snippet = $snippet unless ($abstAll);
    $output .= qq(<BLOCKQUOTE id="test3_$rank" style="display: block;" class="snippet"><SPAN style="border: 0px solid black; background-color:navy; color:white; font-weight:bold; padding:0em 0.5em; margin-right:0.5em;">本文</SPAN>$short_snippet...</BLOCKQUOTE>);
    $output .= qq(<BLOCKQUOTE id="test4_$rank" style="display: none;"  class="snippet"><SPAN style="border: 0px solid black; background-color:navy; color:white; font-weight:bold; padding:0em 0.5em; margin-right:0.5em;">本文</SPAN>$snippet</BLOCKQUOTE>);

    $output .= "</TABLE>";
    $output .= "</DIV>";

    return $output;
}

sub makeShortSnippet {
    my ($this, $string, $MAX_LENGTH_OF_SHORT_SNIPPET) = @_;

    my $ch_count = 0;
    my $inner_tag = 0;
    my $short_snippet;
    foreach my $substr (split /(<[^>]+>)/, $string) {
	if ($substr =~ /^</) {
	    $short_snippet .= $substr;
	    if ($substr =~ /^<\//) {
		$inner_tag = 0;
	    } else {
		$inner_tag = 1;
	    }

	    last if ($ch_count > $MAX_LENGTH_OF_SHORT_SNIPPET && !$inner_tag);
	} else {
	    if ($ch_count + length($substr) > $MAX_LENGTH_OF_SHORT_SNIPPET && !$inner_tag) {
		my $num_of_ch = $MAX_LENGTH_OF_SHORT_SNIPPET - $ch_count;
		$short_snippet .= substr($substr, 0, $num_of_ch);
		last;
	    } else {
		$ch_count += length($substr);
		$short_snippet .= $substr;
	    }
	}
    }

    return $short_snippet;
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

    $writer->startTag('Result', Id => sprintf("%s", $did));
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
    my ($this, $logger, $params, $result, $query, $from, $end, $hitcount) = @_;

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

    my $search_time = $logger->getParameter('search') + $logger->getParameter('parse_query') +  $logger->getParameter('snippet_creation');
    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    if ($params->{show_search_time}) {
	my $etcmax =
	    $logger->getParameter('max_logical_condition') +
	    $logger->getParameter('max_near_condition') +
	    $logger->getParameter('max_merge_dids') +
	    $logger->getParameter('max_document_scoring');
	my $etc =
	    $logger->getParameter('logical_condition') +
	    $logger->getParameter('near_condition') +
	    $logger->getParameter('merge_dids') +
	    $logger->getParameter('document_scoring');

	$writer->startTag('ResultSet', time => $timestamp, query => $queryString,
			  totalResultsAvailable => $hitcount, 
			  totalResultsReturned => $end - $from, 
			  firstResultPosition => $params->{'start'} + 1,
			  logicalOperator => $params->{'logical_operator'},
			  forceDpnd => $params->{'force_dpnd'},
			  dpnd => $params->{'dpnd'},
			  anchor => $params->{flag_of_anchor_use},
			  filterSimpages => $params->{'filter_simpages'},
			  sort_by => $params->{'sort_by'},
			  searchTime => $search_time,
			  parseQueryTime => $logger->getParameter('parse_query'),
			  slaveServerTime => $logger->getParameter('search'),

			  snippetCreationWorstTime => ($logger->getParameter('snippet_creation') eq '') ? 0 : $logger->getParameter('snippet_creation'),
			  connectionWorstTime => $logger->getParameter('max_transfer_time_from') + $logger->getParameter('max_transfer_time_to'),
			  indexAccessWorstTime => $logger->getParameter('max_index_access'),
			  mergeSynonymsWorstTime => $logger->getParameter('max_merge_synonyms'),
			  etcWorstTime => $etcmax,

			  snippetCreationTime => ($logger->getParameter('snippet_creation') eq '') ? 0 : $logger->getParameter('snippet_creation'),
			  connectionTime => $logger->getParameter('transfer_time_from') + $logger->getParameter('transfer_time_to'),
			  indexAccessTime => $logger->getParameter('index_access'),
			  mergeSynonymsTime => $logger->getParameter('merge_synonyms'),
			  etcTime => $etc,
#			  indexSearchTime => $logger->getParameter('search'),
#			  snippetCreationTime => ($logger->getParameter('snippet_creation') eq '') ? 0 : $logger->getParameter('snippet_creation'),
			  site => (defined $params->{site}) ? $params->{site} : 'null'
	    );
    } else {
	$writer->startTag('ResultSet', time => $timestamp, query => $queryString,
			  totalResultsAvailable => $hitcount,
			  totalResultsReturned => $end - $from,
			  firstResultPosition => $params->{'start'} + 1,
			  logicalOperator => $params->{'logical_operator'},
			  forceDpnd => $params->{'force_dpnd'},
			  dpnd => $params->{'dpnd'},
			  anchor => $params->{flag_of_anchor_use},
			  filterSimpages => $params->{'filter_simpages'},
			  sort_by => $params->{'sort_by'},
			  site => (defined $params->{site}) ? $params->{site} : 'null'
	    );
    }

    for (my $rank = $from; $rank < $end; $rank++) {
	my $page = $result->[$rank];
	my $did = sprintf("%s", $page->{did});
	my $url = $page->{url};
	my $score = $page->{score_total};
	my $title = $page->{title};
	my $crawled_date = $page->{crawled_date};
	my $cache_location = $page->{cache_location};
	my $cache_size = $page->{cache_size};

	my %attrs_of_result_tag_order = (Rank => 1, Id => 2, Score => 3, DetailScore => 4);
	my %attrs_of_result_tag = ();
	$attrs_of_result_tag{Id} = $did if ($params->{Id} > 0);
	$attrs_of_result_tag{Rank} = $rank + 1;
	$attrs_of_result_tag{Score} = sprintf("%.5f", $score) if ($params->{Score} > 0);
	$attrs_of_result_tag{DetailScore} = sprintf("Tsubaki:%.5f, PageRank:%s", $page->{tsubaki_score}, $page->{pagerank}) if ($params->{detail_score});

	# 開始タグの表示
	$writer->startTag('Result', map {$_ => $attrs_of_result_tag{$_}} sort {$attrs_of_result_tag_order{$a} <=> $attrs_of_result_tag_order{$b}} keys %attrs_of_result_tag);

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

	##################################################
	# 論文検索用タグ
	##################################################
	if ($CONFIG->{IS_IPSJ_MODE}) {
	    my $abst = $page->{abstAll};
	    my $artid = $page->{artid};
	    my ($authors, $booktitle, $voln, $spage, $epage, $year) = split (" ", $page->{bibdat});
	    my ($volume, $number) = split (",　", $voln);

	    if ($params->{Author} > 0) {
		$writer->startTag('Authors');
		foreach my $author (split (/，/, $authors)) {
		    $writer->startTag('Author');
		    $writer->characters($author);
		    $writer->endTag('Author');
		}
		$writer->endTag('Authors');
	    }

	    if ($params->{Abstract} > 0) {
		$writer->startTag('Abstract');
		$writer->characters($abst);
		$writer->endTag('Abstract');
	    }


	    if ($params->{Year} > 0) {
		$writer->startTag('Year');
		$writer->characters($year);
		$writer->endTag('Year');
	    }

	    if ($params->{Booktitle} > 0) {
		$writer->startTag('Booktitle');
		$writer->characters($booktitle);
		$writer->endTag('Booktitle');
	    }


	    if ($params->{Volume} > 0) {
		$writer->startTag('Volume');
		$writer->characters($volume);
		$writer->endTag('Volume');
	    }


	    if ($params->{Number} > 0) {
		$writer->startTag('Number');
		$writer->characters($number);
		$writer->endTag('Number');
	    }


	    if ($params->{Page} > 0) {
		$writer->startTag('Page');
		$writer->characters(sprintf ("%s-%s", $spage, $epage));
		$writer->endTag('Page');
	    }


	    if ($params->{ArtID} > 0) {
		$writer->startTag('ArtID');
		$writer->characters($artid);
		$writer->endTag('ArtID');
	    }
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

	if ($params->{CrawledDate} > 0) {
	    $writer->startTag('CrawledDate');
	    $writer->characters($crawled_date);
	    $writer->endTag('CrawledDate');
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


sub printIPSJMetadata {
    my ($this, $metadata) = @_;

    my @attrs = ("ID", "IPSJ", "KJ", "NCID", "TITLE", "ETITLE", "AUTH", "EAUTH", "JRNL", "EJRNL", "VOLN", "SPAGE" ,"EPAGE", "URL", "YEAR", "KYWD", "EKYWD", "ABST", "EABST", "CITID", "UCITID");

    my %buf;
    foreach my $tagname (@attrs) {
	while ($metadata =~ m/<$tagname>(.+?)<\/$tagname>/g) {
	    my $value = $1;
	    next if ($value eq '');

	    if ($tagname =~ /AUTH/) {
		while ($value =~ m/<AUTH_NAME>(.+?)<\/AUTH_NAME>/g) {
		    push (@{$buf{$tagname}}, $1);
		}
	    } else {
		$buf{$tagname} = $value;
	    }
	}
    }


    print "<TABLE border=1>\n";
    foreach my $tagname (@attrs) {
	next if (!defined $buf{$tagname} || $buf{$tagname} eq "");

	print "<TR><TD>$tagname</TD><TD>";
	if ($tagname =~ /AUTH/) {
	    print join (", ", @{$buf{$tagname}});
	} else {
	    print $buf{$tagname};
	}
	print "</TD></TR>\n";
    }
    print "</TABLE>\n";
}


# クラスメソッド
sub printErrorMessage {
    my ($cgi, $msg) = @_;

    print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
    print $msg . "\n";
}

1;
