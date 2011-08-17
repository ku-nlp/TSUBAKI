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
use Tsubaki::TermGroupCreater;

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
	    printf("のうち");
	    printf(" <B>%s</B> を含む文書", decode('utf8', $params->{cluster_label})) if (defined $params->{cluster_label});
	    printf(" %d - %d 件目\n", $params->{'start'} + 1, $end);
	} else {
	    if (defined $params->{cluster_label}) {
		printf("のうち <B>%s</B> を含む文書", decode('utf8', $params->{cluster_label}));
	    }
	}

	print qq(<INPUT type="button" class='button' value="クエリ解析結果の確認・修正" onclick="javascript:showQueryEditWindow();">) unless $CONFIG->{IS_ENGLISH_VERSION};
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
			if (defined $params->{cluster_id}) {
			    push (@buf, sprintf ("cluster_id=%d", $params->{cluster_id}));
			}
			if (defined $params->{cluster_id}) {
			    push (@buf, sprintf ("cluster_label=%s", &uri_escape($params->{cluster_label})));
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

    # クレジットの出力
    $this->print_copyright();
}

# copyrightの出力
sub print_copyright {
    my ($this) = @_;

    print << "END_OF_HTML";
<DIV style="text-align:center;padding:1em;">
    TSUBAKI利用時の良かった点、問題点などご意見を頂けると幸いです。<br>
    ご意見は tsubaki-feedback あっと nlp.kuee.kyoto-u.ac.jp までお願い致します。
    <P>
    <DIV><B>&copy;2006 - 2011 黒橋研究室</B></DIV> 
</DIV>
</BODY>
</HTML>
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
	    push(@buf, sprintf (qq(<SPAN class="query" id="query%d">%s</SPAN>), $i, $kwd->{rawstring}));
	}
	print join('&nbsp;', @buf);
    } elsif ($query->{s_exp}) {
	printf qq(<SPAN class="query" id="query%d">%s</SPAN>), 0, $query->{rawstring};
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
	}
    }

    untie %$synonyms if (defined $synonyms);
}

sub printJavascriptCode {
    my ($canvasName, $query, $opt, $disable_css_loading_code) = @_;

    print << "END_OF_HTML";
    <style type="text/css">
	DIV.term {
	  text-align: center;
	  margin: 0.1em;
    }

    DIV.termBasic {
	text-align: center;
        margin: 0.1em;
    }

    DIV.termGroup {
      text-align: center;
      padding: 0em 0.1em;
      margin: 0.5em;
      border: 1px solid blue;
      float: left;
      font-size: 10pt;
    }

    DIV.imp {
	text-align: center;
      cursor: pointer;
    }
</style>

    <script language="JavaScript" type="text/javascript">
END_OF_HTML
unless ($query->{rawstring}) {
    print "</script>\n";
    return;
}

    print "var jg;\n";
    print "function init () {\n";
    printf "jg = new jsGraphics('%s');\n", $canvasName;
    if ($CONFIG->{IS_CPP_MODE}) {
	printf "Event.observe('query%d', 'click',  showQueryEditWindow);\n", 0;
	print "}\n";
    } else {
	for (my $i = 0; $i < scalar(@{$query->{keywords}}); $i++) {
	    printf "Event.observe('query%d', 'click',  showQueryEditWindow);\n", 0;
#	    printf "Event.observe('query%d', 'mouseout',  hide_query_result);\n", $i;
#	    printf "Event.observe('query%d', 'mousemove', show_query_result%d);\n", $i, $i;
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
	    print "baroon.style.left = (x + 'px');";
	    print "baroon.style.top = ((y + 20) + 'px');";

	    print "var canvas = document.getElementById('canvas');\n";
	    print "canvas.style.width = $width + 'px';\n";
	    print "canvas.style.height = $height + 'px';\n";

	    print $jscode;
	    print "}\n";
	}
    }
    print "</script>\n";
}

# TSUBAKIの初期画面
sub print_initial_display {
    my ($this) = @_;

    $this->print_tsubaki_interface();
    $this->print_copyright();
}

# TSUBAKIの画面
sub print_tsubaki_interface {
    my ($this, $params, $query, $status) = @_;

    # header の出力
    $this->print_header($query, $params);

    # body の出力
    $this->print_body($params, $query, $status);
}

# header の出力
sub print_header {
    my ($this, $query, $opt) = @_;

    my $canvasName = 'canvas';
    my $title = "情報爆発プロジェクト 検索エンジン基盤 TSUBAKI";
    $title .= " (情報処理学会 論文検索版)" if ($CONFIG->{IS_IPSJ_MODE});

    print << "END_OF_HTML";
<HTML>
    <HEAD>
    <TITLE>$title</TITLE>
    <META http-equiv="Content-Type" content="text/html; charset=utf-8">
    <LINK rel="stylesheet" type="text/css" href="css/tsubaki.common.css">
    <LINK rel="icon" href="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/favicon.ico" type="image/x-icon" />  
    <LINK rel="Shortcut Icon" type="img/x-icon" href="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/favicon.ico" />  
END_OF_HTML

    print << "END_OF_HTML";
	<script language="JavaScript">
	    var regexp = new RegExp("Gecko");
	if (navigator.userAgent.match(regexp)) {
	    document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.gecko.css'>");
	} else {
	    document.write("<LINK rel='stylesheet' type='text/css' href='css/tsubaki.ie.css'>");
	}
	</script>
	<script type="text/javascript" src="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/wz_jsgraphics.js"></script>
	<script type="text/javascript" src="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/prototype.js"></script>
	<script type="text/javascript" src="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/tsubaki.js"></script>
END_OF_HTML

    # クエリ解析結果を描画するjavascriptコードの出力
    unless ($CONFIG->{IS_ENGLISH_VERSION}) {
	# my ($width, $height, $jscode) = $query->{keywords}[0]->getPaintingJavaScriptCode() if (defined $query->{keywords}[0]);
	&printJavascriptCode('canvas', $query, $opt);
    }
    print "</HEAD>\n";
}

# body の出力
sub print_body {
    my ($this, $params, $query, $status) = @_;

    print qq(<BODY style="padding: 0.2em 0.6em; margin:0em; z-index:1;" onload="javascript:init();javascript:init2('query_edit_canvas'); javascript:createTerms();">\n);
    print << "END_OF_HTML";

<TABLE cellpadding="0" cellspacing="0" border="0" id="query_edit_window" style="z-index: 2; display:none; position: absolute; top: 20%; align: center; left: 20%; display: none;">
    <TR>
	<TD><IMG width="24" height="42" src="image/curve-top-left.png"></TD>
<TD style="background-color:#ffffcc;">
<CENTER style="padding-top: 1em;">
   <INPUT type="button" class="button" value="修正結果で検索する" onclick="javascript:submitQuery2();">
   <INPUT type="button" class="button" value="閉じる" onclick="javascript:hideQueryEditWindow();">
</CENTER>
</TD>
	<TD><IMG width="24" height="42" src="image/curve-top-right.png"></TD>
    </TR>
    <TR>
	<TD style="background-color:#ffffcc;"></TD>
	<script language="JavaScript">
	    var regexp = new RegExp("Gecko");
	if (navigator.userAgent.match(regexp)) {
	    document.write('<TD style="background-color:#ffffcc;"><CENTER><DIV id="query_edit_canvas" style="position: relative; padding-top:7em;"></DIV></CENTER></TD>');
	} else {
	    document.write('<TD style="background-color:#ffffcc;" id="query_edit_canvas" style="position: relative; padding-top:7em;"><BR></TD>');
	}
	</script>

	<TD style="background-color:#ffffcc;"></TD>
    </TR>
    <TR>
	<TD><IMG width="24" height="24" src="image/curve-bottom-left.png"></TD>
	<TD style="background-color:#ffffcc;"></TD>
	<TD><IMG width="24" height="24" src="image/curve-bottom-right.png"></TD>
    </TR>
</TABLE>
END_OF_HTML

    # クエリ解析結果表示用の領域を確保
    $this->print_canvas();

#   print qq(<DIV style="font-size:11pt; width: 100%; text-align: right; padding:0em 0em 0em 0em;">\n);
    print qq(<DIV style="font-size:11pt; width: 100%; border: 0px solid red; text-align: right; margin-top:5pt; marging-right: 5pt;">\n);
#    if ($status eq 'search' || $status eq 'cache') {
#	print qq(<A href="http://tsubaki.ixnlp.nii.ac.jp/index.cgi">2007年度文書セットはこちら</A>); # unless ($CONFIG->{IS_NICT_MODE});
#	print qq(&nbsp;|&nbsp;);
#    }
    print qq(<A href="tutorial.html">使い方</A><BR>\n);

    # 混雑具合を表示
    $this->print_congestion() if ($CONFIG->{DISPLAY_CONGESTION});

    print qq(</DIV>\n);

    print qq(<TABLE width="100%" border="0"><TR>\n);

    # logo出力
    $this->print_logo($params);

    # フォーム出力
    $this->print_form($params);

    # アンケート用ボックスを表示
    $this->print_questionnarie_box() if ($CONFIG->{QUESTIONNAIRE} && ($status eq 'search' || $status eq 'cache'));

    print qq(</TR></TABLE>\n);

    # メッセージがあれば出力
    print qq(<CENTER><FONT color="red">$CONFIG->{MESSAGE}</FONT></CENTER>\n) if ($CONFIG->{MESSAGE});
}

# クエリ解析結果表示用の領域を確保
sub print_canvas {
    my ($this) = @_;

    print << "END_OF_HTML";
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
}

# logoの表示
sub print_logo {
    my ($this, $params) = @_;

    if ($params->{query}) {
	print qq(<TD width="220" align="center" valign="middle" style="border: 0px solid red;">\n);
	printf ("<A href=%s><IMG border=0 src=image/logo-mini.png></A><BR>\n", $CONFIG->{INDEX_CGI});
	print qq(<SPAN style="color:#F60000; font-size:small; font-weight:bold;">- 2010年度版 -</SPAN></TD>\n);
	if ($CONFIG->{IS_IPSJ_MODE}) {
	    print qq(<SPAN style="color:#F60000; font-size:x-small; font-weight:bold;">- 情報処理学会 論文検索版 -</SPAN></TD>\n);
	}
    }
    else {
	print qq(<TD align="center">);
	printf ("<A href=%s><IMG border=0 src=image/logo.png></A>\n", $CONFIG->{INDEX_CGI});
	print qq(<SPAN style="color:#F60000; font-size:small; font-weight:bold;">2010年度版</SPAN>\n);
	print qq(<BR><SPAN style="color:#F60000; font-size:x-small; font-weight:bold;">- 情報処理学会 論文検索版 -</SPAN>\n) if ($CONFIG->{IS_IPSJ_MODE});
	print "</TD></TR>\n";
	print "<TR>";
    }
}

# formの表示
sub print_form {
    my ($this, $params) = @_;

    printf qq(<TD width="*" align="%s" valign="middle" style="border: 0px solid red; padding-top: 1em;">\n), (($params->{query}) ? 'left' : 'center');

    print qq(<FORM name="search" method="GET" action="" enctype="multipart/form-data" onSubmit="submitQuery();">\n);
    print qq(<INPUT type="hidden" id="num_of_start_page" name="start" value="1">\n);
    print qq(<INPUT type="hidden" id="rm_synids" name="remove_synids" value="">\n);
    print qq(<INPUT type="hidden" id="trm_states" name="term_states" value="">\n);
    print qq(<INPUT type="hidden" id="dep_states" name="dpnd_states" value="">\n);
    print qq(<INPUT type="text" style="border: 1px solid black;padding:0.1em; width: 40em;" id="qbox" name="query" value="$params->{'query'}" size="112">\n);

    print qq(<INPUT type="button" class="button" value="検索" onclick="submitQuery();"/>\n);
    # print qq(<INPUT type="button" value="クリア" onclick="document.all.query.value=''"/><BR>\n);

    # NTCIRモードの場合はクエリを表示
    $this->print_ntcir_queries($params) if ($CONFIG->{IS_NTCIR_MODE});

    # 検索に利用するブロックタイプを選択するチェックボックスを表示
    $this->printBlockTypeCheckbox($params);

    # 省略解析結果を利用するかどうかのチェックボックスを表示
    $this->printAnaphoraResolutionUseCheckbox($params) unless ($CONFIG->{DISABLE_ANAPHORA_RESOLUTION_DISPLAY});

    # 開発モード用オプションを表示
    $this->print_options_for_developmode($params) if ($params->{develop_mode});

    print qq(</FORM>\n);
    print qq(</TD>\n);
}

# NTCIRのクエリを表示
sub print_ntcir_queries {
    my ($this, $params) = @_;

    print qq(<SELECT name="ntcir_query" style="display: inline; margin-top: 0.2em;">\n);
    open (READER, "<:encoding(euc-jp)", $CONFIG->{TSUBAKI_SCRIPT_PATH} . "/../data/qs-fml-ntcir34") or die "$!";
    while (<READER>) {
	chop;
	my ($qid, $string) = split (/ /, $_);
	if ($string eq $params->{ntcir_query}) {
	    printf qq(<OPTION value="%s" selected>%s: %s\n), $string, $qid, $string;
	} else {
	    printf qq(<OPTION value="%s">%s: %s\n), $string, $qid, $string;
	}
    }
    close (READER);
    print "</SELECT> ";
    print qq(<INPUT type="button" value="入力" onclick="document.search.qbox.value = document.search.ntcir_query.options[document.search.ntcir_query.selectedIndex].value;"/><BR>\n);
}

# 開発モード用オプションを表示
sub print_options_for_developmode {
    my ($this, $params) = @_;

    print qq(<TABLE style="border=0px solid silver;padding: 0.25em;margin: 0.25em;"><TR><TD>検索条件</TD>\n);
    if ($params->{'logical_operator'} eq "OR") {
	print qq(<TD><LABEL><INPUT type="radio" name="logical" value="DPND_AND"/>全ての係り受けを含む</LABEL></TD>\n);
	print qq(<TD><LABEL><INPUT type="radio" name="logical" value="WORD_AND"/>全ての語を含む</LABEL></TD>\n);
	print qq(<TD><LABEL><INPUT type="radio" name="logical" value="OR" checked/>いずれかの語を含む</LABEL></TD>\n);
    }
    elsif ($params->{'logical_operator'} =~ /AND/) {
	if ($params->{'force_dpnd'}) {
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="DPND_AND" checked/>全ての係り受けを含む</LABEL></TD>\n);
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="WORD_AND"/> 全ての語を含む</LABEL></TD>\n);
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="OR"/>いずれかの語を含む</LABEL></TD>\n);
	} else {
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="DPND_AND"/>全ての係り受けを含む</LABEL></TD>\n);
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="WORD_AND" checked/> 全ての語を含む</LABEL></TD>\n);
	    print qq(<TD><LABEL><INPUT type="radio" name="logical" value="OR"/>いずれかの語を含む</LABEL></TD>\n);
	}
    }
    print "</TR>";

    print qq(<TR><TD>オプション</TD><TD colspan="3" style="text-align:left;">);
    if ($CONFIG->{DISABLE_SYNGRAPH_SEARCH}) {
	print qq(<LABEL><INPUT type="checkbox" name="disable_synnode" disabled></INPUT><FONT color="silver">同義表現を考慮しない</FONT></LABEL>);
    } else {
	if ($params->{disable_synnode}) {
	    print qq(<LABEL><INPUT type="checkbox" name="disable_synnode" checked></INPUT><FONT color="black">同義表現を考慮しない</FONT></LABEL>);
	} else {
	    print qq(<INPUT type="checkbox" name="disable_synnode"></INPUT><LABEL><FONT color="black">同義表現を考慮しない</FONT></LABEL>);
	}
    }

    if ($params->{antonym_and_negation_expansion}) {
	print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion" checked></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
    } else {
	print qq(<INPUT type="checkbox" name="antonym_and_negation_expansion"></INPUT><LABEL><FONT color="black">反義語・否定を考慮する</FONT></LABEL>);
    }

    if ($CONFIG->{DISABLE_KWIC_DISPLAY}) {
	print qq(<INPUT type="checkbox" name="kwic" disabled></INPUT><FONT color="silver">KWIC表示</FONT></LABEL>);
    } else {
	if ($params->{kwic}) {
	    print qq(<INPUT type="checkbox" name="kwic" checked></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	} else {
	    print qq(<INPUT type="checkbox" name="kwic"></INPUT><LABEL><FONT color="black">KWIC表示</FONT></LABEL>);
	}
    }
    print "</TD></TR></TABLE>\n";
}


# アンケートボックスの表示
sub print_questionnarie_box {
    my ($this) = @_;

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

# 領域タイプを選択するチェックボックスを表示
sub printBlockTypeCheckbox {
    my ($this, $params) = @_;

    if ($CONFIG->{USE_OF_BLOCK_TYPES} && !$CONFIG->{DISABLE_BLOCK_TYPE_DISPLAY}) {
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

# 省略解析結果を利用する／しないを選択するチェックボックスを表示
sub printAnaphoraResolutionUseCheckbox {
    my ($this, $params) = @_;

    print qq(<DIV style="padding-top:1em;">省略解析結果　);
    if ($params->{use_of_anaphora_resolution}) {
	print qq(<LABEL><INPUT type="radio" name="use_of_anaphora_resolution" value="on" checked></INPUT><FONT color="black">利用する</FONT></LABEL>);
	print qq(<LABEL><INPUT type="radio" name="use_of_anaphora_resolution" value="off"></INPUT><FONT color="black">利用しない</FONT></LABEL>);
    } else {
	print qq(<LABEL><INPUT type="radio" name="use_of_anaphora_resolution" value="on"></INPUT><FONT color="black">利用する</FONT></LABEL>);
	print qq(<LABEL><INPUT type="radio" name="use_of_anaphora_resolution" value="off" checked></INPUT><FONT color="black">利用しない</FONT></LABEL>);
    }
    print qq(</DIV>\n);
}

sub print_congestion {
    my ($this) = @_;

    my ($count, $foregroundColor, $backgroundColor) = &getCongestion();
    print qq(<SPAN style="color: $foregroundColor; background-color: $backgroundColor;">&nbsp;混具合:&nbsp;$count クエリ/分</SPAN>);
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
	return $sni_obj->get_snippets_for_each_did($query, {highlight => $opt->{highlight}, debug => $opt->{debug}});
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

sub printAjax {
    my ($this, $params, $dids) = @_;

    # クエリ修正結果を取得
    my @removeSynids = ();
    foreach my $k (sort keys %{$params->{remove_synids}}) {
	push (@removeSynids, sprintf ("%s:%s", $k, $params->{remove_synids}{$k}));
    }
    my @termStates = ();
    foreach my $k (sort keys %{$params->{term_states}}) {
	push (@termStates, sprintf ("%s:%s", $k, $params->{term_states}{$k}));
    }
    my @dpndStates = ();
    foreach my $k (sort keys %{$params->{dpnd_states}}) {
	push (@dpndStates, sprintf ("%s:%s", $k, $params->{dpnd_states}{$k}));
    }

    print << "END_OF_HTML";
<SCRIPT>
new Ajax.Request(
    "call-webclustering.cgi",
    {
         onSuccess  : processResponse,
         onFailure  : notifyFailure,
         parameters : "query=$params->{query}&dids=$dids&org_referer=$params->{escaped_org_referer}"
    }
);

function processResponse(xhrObject)
    {
	Element.update('msg', xhrObject.responseText);
    }

function notifyFailure()
    {
        alert("An error occurred!");
    }
</SCRIPT>
END_OF_HTML
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

    $this->printQueryEditPain($params, $query) unless $CONFIG->{IS_ENGLISH_VERSION};

    # for ajax
    my @__buf;
    my $rank = 1;
    foreach my $doc (@$results) {
	push (@__buf, $doc->{did});
	$rank++;
	# last if ($rank > 100);
    }
    $this->printAjax($params, join (",", @__buf)) if ($status ne "busy") && !$CONFIG->{IS_ENGLISH_VERSION};

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


    my $evaldat = ();
    my %evalmap = ();
    if ($CONFIG->{IS_NTCIR_MODE}) {
#	tie my %_cdb, 'CDB_File', $CONFIG->{NTCIR_EVAL_DAT} or die $!;
	tie my %_cdb, 'CDB_File', "/home/skeiji/public_html/tsubaki-ntcir/SearchEngine/cgi/ntcir34-query-eval.cdb" or die $!;
	require Storable;
	$evaldat = Storable::thaw($_cdb{$params->{ntcir_query}});
	untie %_cdb;

	$evalmap{'H'} = '◎';
	$evalmap{'S'} = '◎';
	$evalmap{'A'} = '○';
	$evalmap{'B'} = '△';
	$evalmap{'C'} = 'Ｘ';
    }


    if ($CONFIG->{IS_NTCIR_MODE}) {
	my %num_of_judges = ();
	for (my $rank = $start; $rank < $end; $rank++) {
	    my $did = $results->[$rank]{did};
	    my $judge = $evalmap{$evaldat->{sprintf("%09d", $did)}};
	    $judge = '？' unless ($judge);
	    $num_of_judges{$judge}++;
	}

	print qq(<DIV style="font-size:small; text-align: left; background-color:#f1f4ff; mergin:0px; margin-top:-0.2em; padding-left:1em;">\n);
	print "評価結果：";
	foreach my $judge (('◎', '○', '△', 'Ｘ', '？')) {
	    my $num = $num_of_judges{$judge};
	    $num = 0 unless (defined $num);

	    printf "%s %s　", $judge, $num;
	}
	print "</DIV>\n";
    }

    ################
    # 検索結果を表示
    ################
    print "<TABLE border='0'><TR><TD valign='top'>";
    my $uri_escaped_search_keys = ($CONFIG->{IS_CPP_MODE}) ? $query->{escaped_query} : $this->get_uri_escaped_query($query);
    for (my $rank = $start; $rank < $end; $rank++) {
	my $did = $results->[$rank]{did};

	my $score = sprintf("score = %.4f", $results->[$rank]{score_total});
	my $snippet = $did2snippets->{$did};
	my $title = $results->[$rank]{title};
	# タイトルが長い場合は ... で省略する
	$title = substr($title, 0, $CONFIG->{MAX_LENGTH_OF_TITLE}) . "..." if (length($title) > $CONFIG->{MAX_LENGTH_OF_TITLE});


	my $output = qq(<DIV class="result">);

	###############################################################################
	# 順位とタイトル
	###############################################################################

	$output .= qq(<TABLE cellpadding="0" border="0" width="100%">\n);
	$output .= qq(<TR><TD style="width: 1em; text-align: center;"><SPAN class="rank" nowrap>) . ($rank + 1) . "</SPAN></TD>\n";

	$output .= qq(<TD>\n);
	if ($CONFIG->{IS_NTCIR_MODE}) {
	    $output .= qq(<A class="title" href="http://nlpc06.ixnlp.nii.ac.jp/cgi-bin/skeiji/ntcir/ntcir-api.cgi?action=show_page&id=$did&format=html" class="ex">);
	    my $judge = $evalmap{$evaldat->{sprintf("%09d", $did)}};
	    $judge = '？' unless ($judge);
	    $title = sprintf ("%s: %s", $judge, $title);
	} else {
	    if ($CONFIG->{LINK_CACHED_HTML_FROM_TITLE}) { # タイトルからキャッシュへのリンクをはるとき
		$output .= qq(<A class="title" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank" class="ex">);
	    }
	    else { # 元ページへのリンク
		$output .= qq(<A class="title" href="$results->[$rank]{url}" target="_blank" class="ex">);
	    }
	}
	# 全角英数字を半角に
	$title =~ tr/[Ａ-Ｚａ-ｚ０-９．／＠　]/[A-Za-z0-9.\/@ ]/;
	$title =~ s/_/ / if $CONFIG->{IS_ENGLISH_VERSION}; # extract-url-title.perlでスペースを_に置換しているのを戻す
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
	    $output .= sprintf qq(id=%s, %s), $did, $score;
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
		$output .= sprintf qq($score (w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f)), $score_w, $score_d, $score_n, $score_aw, $score_dw;
	    } else {
		$output .= sprintf qq($score (w=%.3f, d=%.3f, n=%.3f, aw=%.3f, ad=%.3f, pr=%s)), $score_w, $score_d, $score_n, $score_aw, $score_dw, $score_pr;
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

	if ($params->{debug}) {
	    my $terms = $results->[$rank]{terminfo}{terms};
	    my $dleng = $results->[$rank]{terminfo}{length};
	    my $pgrnk = $results->[$rank]{terminfo}{pagerank};
	    my $flagOfStrictTerm = $results->[$rank]{terminfo}{flagOfStrictTerm};
	    my $flagOfProxConst = $results->[$rank]{terminfo}{flagOfProxConst};
	    my %buff;
	    foreach my $gid (sort {$a <=> $b} keys %$terms) {
		my $frq = $terms->{$gid}{frq};
		my $tff = $terms->{$gid}{tff};
		my $gdf = $terms->{$gid}{gdf};
		my $idf = $terms->{$gid}{idf};
		my $okp = $terms->{$gid}{okp};

		my @_buf;
		if ($CONFIG->{IS_CPP_MODE}) {
		    my $string = $terms->{$gid}{str};
		    $string =~ s/</&lt;/g;
		    $string =~ s/>/&gt;/g;
		    push (@_buf, $string);
		} else {
		    foreach my $qid (sort {$terms->{$gid}{qinfo}{$b} <=> $terms->{$gid}{qinfo}{$a}} keys %{$terms->{$gid}{qinfo}}) {
			my $string = $query->{qid2rep}{$qid};
			$string =~ s/</&lt;/g;
			$string =~ s/>/&gt;/g;
			push (@_buf, sprintf("%s %s", $string, $terms->{$gid}{qinfo}{$qid}));
		    }
		}

		my %term2pos;
		while (my ($term, $pos) = each %{$results->[$rank]{terminfo}{term2pos}}) {
		    $term2pos{$term} = join (",", @$pos) if (defined $pos);
		}

		my $line = sprintf "<TR><TD align='right' style='padding-left:1em;'>%.2f</TD><TD align='right' style='padding-left:1em;'>%.2f</TD><TD align='right' style='padding-left:1em;'>%.2f</TD><TD align='right' style='padding-left:1em;'>%s</TD><TD align='right' style='padding-left:1em;'>%.2f</TD><TD align='left' style='padding-left:1em;'>%s</TD><TD align='left' style='padding-left:1em;'>%s</TD></TR>\n", $okp, $frq, $tff, $gdf, $idf, (join (" ", @_buf)), $term2pos{$terms->{$gid}{str}};
		if ($gid =~ /\//) {
		    push (@{$buff{dpnds}}, $line);
		} else {
		    push (@{$buff{words}}, $line);
		}
	    }
	    $output .= sprintf "length=%.2f, pageRank=%s, strictTerm=%s, proxConst=%s<BR>\n", $dleng, $pgrnk, $flagOfStrictTerm, $flagOfProxConst;
	    $output .= "<TABLE>\n";
	    $output .= "<TR><TH>okp</TH><TH>frq</TH><TH>tff</TH><TH>gdf</TH><TH>idf</TH><TH>terms</TH><TH>position</TH></TR>\n";
	    foreach my $type (('words', 'dpnds')) {
		foreach my $line (@{$buff{$type}}) {
		    $output .= $line;
		}
	    }
	    $output .= "</TABLE>\n";
	}

	###############################################################################
	# スニペット
	###############################################################################

	$output .= qq(<BLOCKQUOTE class="snippet">$snippet</BLOCKQUOTE>);
	my $_url = $results->[$rank]{url};
        $_url = substr($_url, 0, $CONFIG->{MAX_LENGTH_OF_URL}) . "..." if (length($_url) > $CONFIG->{MAX_LENGTH_OF_URL});
	if ($CONFIG->{LINK_CACHED_HTML_FROM_TITLE}) { # タイトルがキャッシュページのときは、こちらを元ページへのリンクにする
	    $output .= qq(<A class="cache" href="$results->[$rank]{url}" target="_blank">$_url</A>\n);
	}
	else { # タイトルが元ページへのリンクのときは、こちらはリンクなし
	    $output .= qq(<SPAN class="cache">$_url</SPAN>\n);
	}
#	$output .= qq(<A class="cache2" href="index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys . qq(" target="_blank">キャッシュ</A>\n);

	if ($CONFIG->{USE_OF_BLOCK_TYPES} && !$CONFIG->{IS_KUHP_MODE}) {
	    # ページの構造解析結果へのリンクを生成
	    my $basecgi = 'http://orchid.kuee.kyoto-u.ac.jp/~funayama/ISA/index_dev.cgi?';
	    my $pageurl = "http://nlpc06.ixnlp.nii.ac.jp/cgi-bin/skeiji/ntcir/ntcir-api.cgi?action=show_page\@id=$did\@format=html";
	    my $block_type_detect_url = sprintf ("%sDetectBlocks_ROOT=%%2Fhome%%2Ffunayama%%2FDetectBlocks&DetectSender_ROOT=%%2Fhome%%2Ffunayama%%2FDetectSender&inputurl=%s&DetectSender_flag=&rel2abs=&input_type=url", $basecgi, $pageurl);

#	    $output .= qq(&nbsp;<A class="cache" href="$block_type_detect_url" target="_blank"><SMALL>構造解析結果</SMALL></A>\n);
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
    if ($logger->getParameter('hitcount') > 0 && !$CONFIG->{IS_ENGLISH_VERSION}) {
    print << "END_OF_HTML";
</TD>
<TD valign='top' width='300'>

<TABLE width="100%" cellpadding="0" cellspacing="0">
<TR>
<TD width="7"><IMG src="image/top-left.png"></TD>
<TD width="*" style='border-top:1px solid silver;'><IMG src="image/bottom-left.png" width=1></TD>
<TD width="7"><IMG src="image/top-right.png"></TD></TR>

<TR>
<TD style='border-left:1px solid silver;'><IMG src="image/bottom-left.png" width=1></TD>
<TD><DIV id='msg'><CENTER><IMG width='1em' src='image/loading.gif' border='0'>&nbsp;関連語蒸留中...</CENTER></DIV></TD>
<TD style='border-right:1px solid silver;'><IMG src="image/bottom-left.png" width=1></TD>
</TR>

<TR>
<TD><IMG src="image/bottom-left.png"></TD>
<TD style='border-bottom:1px solid silver;'><IMG src="image/bottom-left.png" width=1></TD>
<TD><IMG src="image/bottom-right.png"></TD>
</TR>
</TABLE>
</TD>
</TR>
</TABLE>;
END_OF_HTML
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
    $output .= sprintf qq(<A href="javascript:void($rank);" onclick="toggle_ipsj_verbose_view('test1_$rank', 'test2_$rank', 'test3_$rank', 'test4_$rank', this, '%s', '%s');">[ABST・本文の詳細]</A>\n), "[ABST・本文の詳細]", "[元に戻す]" if ($abstAll);
    $output .= sprintf qq(<FONT color="white">%s</FONT>), $result->{did};
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

    $output .= sprintf qq(<BLOCKQUOTE class="bib">);
    $output .= "$_authors;" if ($_authors);
    $output .= "$result->{booktitle} " if ($result->{booktitle});
    $output .= "$result->{volume} " if ($result->{volume});
    $output .= "($result->{number})" if ($result->{number});

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
    my ($this, $logger, $params, $result, $query, $hitcount) = @_;

    my $result = $this->getSearchResultForAPICall($logger, $params, $result, $query, $hitcount);

    print $result;
}

sub getSearchResultForAPICall {
    my ($this, $logger, $params, $result, $query, $hitcount) = @_;

    my $from = $params->{start};
    my $end = (scalar(@$result) < $params->{results}) ?  scalar (@$result) : $params->{results}; # paramsのresultsはstartを足したもの (RequestParser:setParametersOfGetRequest)

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
    my $search_result_string;
    my $writer = new XML::Writer(OUTPUT => \$search_result_string, DATA_MODE => 'true', DATA_INDENT => 2);
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


    # エラーメッセージを出力
    if (scalar($logger->getParameter('ERROR_MSGS')) > 0) {
	my $eid = 1;
	$writer->startTag('ErrorMessages');
	foreach my $errObj (@{$logger->getParameter('ERROR_MSGS')}) {
	    my $owner = $errObj->{owner};
	    my $msg = $errObj->{msg};

	    $writer->startTag('ErrorMessage', id => $eid++, owner => $owner);
	    $writer->characters($msg);
	    $writer->endTag('ErrorMessage');
	}
	$writer->endTag('ErrorMessages');
    }


    # 検索スレーブサーバーのログを表示
    if ($params->{serverLog}) {
	$writer->startTag('ServerLog');
	my $host2log = $logger->getParameter('host2log');
	foreach my $host (keys %$host2log) {
	    my $localLoggers = $host2log->{$host};
	    foreach my $localLogger (sort {$a->getParameter('port') <=> $b->getParameter('port')} @$localLoggers) {
		my $port = $localLogger->getParameter('port');
		$writer->startTag('SlaveServer');

		$writer->startTag('HostName');
		$writer->characters($host);
		$writer->endTag('HostName');

		$writer->startTag('Port');
		$writer->characters($port);
		$writer->endTag('Port');

		$writer->startTag('ServerLog');
		$writer->startTag('SearchTime');
		$writer->characters($localLogger->getParameter('total_time'));
		$writer->endTag('SearchTime');
		$writer->endTag('ServerLog');

		$writer->endTag('SlaveServer');
	    }
	}
	$writer->endTag('ServerLog');
    }


    for (my $rank = $from; $rank < $end; $rank++) {
	my $page = $result->[$rank];
	my $did = sprintf("%s", $page->{did});
	my $url = $page->{url};
	my $score = $page->{score_total};
	my $title = $page->{title};
	my $crawled_date = $page->{crawled_date};
	my $uri_escaped_search_keys = ($CONFIG->{IS_CPP_MODE}) ? $query->{escaped_query} : $this->get_uri_escaped_query($query);
	my $cache_location = sprintf ("%s?cache=%s&KEYS=%s", $CONFIG->{INDEX_CGI}, $did, $uri_escaped_search_keys);
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

	if ($params->{TermPosition} > 0) {
	    $writer->startTag('Terms');
	    foreach my $midasi (sort {$a cmp $b} keys %{$page->{terminfo}{term2pos}}) {
		next if ($midasi eq 'none' || $midasi =~ /_LK/);
		my $pos = $page->{terminfo}{term2pos}{$midasi};
		# my ($_midasi) = (($midasi =~ /:[A-Z][A-Z]$/) ? ($midasi =~ /^(.+):..$/) : $midasi);
		my $_midasi = $midasi;
		if (exists($query->{synnode2midasi}{$_midasi})) {
		    $writer->startTag('Term',
				      midasi   => $midasi,
				      orig     => $query->{synnode2midasi}{$_midasi},
				      position => join (",", @$pos)
			);
		} else {
		    $writer->startTag('Term',
				      midasi   => $midasi,
				      position => join (",", @$pos)
			);
		}
		$writer->endTag('Term');
	    }
	    $writer->endTag('Terms');
	}

	if ($params->{Positions} > 0) {
	    my @posbuf;
	    foreach my $dat (@{$result->[$rank]{positions}}) {
		push (@posbuf, $dat->{pos});
	    }

	    $writer->startTag('Positions');
	    $writer->characters(join(",", @posbuf));
	    $writer->endTag('Positions');

	    $writer->startTag('Start');
	    $writer->characters($page->{start});
	    $writer->endTag('Start');

	    $writer->startTag('End');
	    $writer->characters($page->{end});
	    $writer->endTag('End');
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
		    next if ($author eq '');

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
		if (defined $spage && defined $epage) {
		    $writer->startTag('Page');
		    $writer->characters(sprintf ("%s-%s", $spage, $epage));
		    $writer->endTag('Page');
		}
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

    return $search_result_string;
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



sub printQueryEditPain {
    my ($this, $params, $query) = @_;

    my $jscode = $this->getPaintingJavaScriptCode($query->{result}, $params);

    print $jscode . "\n";
}


sub getPaintingJavaScriptCode {
    my ($this, $result, $opt) = @_;

    my $jscode;
    $jscode .= qq(<script type="text/javascript" src="http://nlp.kuee.kyoto-u.ac.jp/~skeiji/drawResult.js"></script>\n);
    $jscode .= qq(<script language="JavaScript">\n);

    # 単語・同義表現グループを描画する
    my @kihonkus = $result->tag;
    my $syngraph = Configure::getSynGraphObj();
    
    my %tid2syns = ();
    my @surfs = ();
    my %synos = ();
    my %tag2i = ();
    for (my $i = 0; $i < scalar(@kihonkus); $i++) {
	my $tag = $kihonkus[$i];
	$tag2i{$tag} = $i;
	my ($synbuf, $max_num_of_words) = &_getExpressions($i, $tag, \%tid2syns, $syngraph, $opt);

	my ($white_space_flag, $_surf) = (1, '');
	foreach my $m ($tag->mrph) {
	    if ($white_space_flag && $m->fstring !~ /内容語/) {
		$_surf .= ' ';
		$white_space_flag = 0;
	    }
	    $_surf .= $m->midasi;
	}
	push (@surfs, $_surf);
	$synos{$surfs[-1]}->{importance} = ($tag->fstring() =~ /クエリ削除語/) ? "UNNECCESARY" : (($tag->fstring() =~ /クエリ不要語/) ?  "OPTIONAL" : "NECCESARY");
	$synos{$surfs[-1]}->{synonyms} = $synbuf;
    }

    $jscode .= qq(function createTerms () {\n);
    $jscode .= qq(var termGroups = new Array\(\);\n);
    $jscode .= qq(var basicWords = new Array\() . join (",", map {sprintf "\"%s\"", $_} @surfs) . qq(\);\n);
    $jscode .= qq(var importance = new Array\() . join (",", map {sprintf "%s", $synos{$_}->{importance}} @surfs) . qq(\);\n);
    $jscode .= qq(for (var i = 0; i < basicWords.length; i++) {\n);
    $jscode .= qq(\ttermGroups[i] = new TermGroup(i, basicWords[i], importance[i]);\n);
    $jscode .= qq(}\n\n);

    foreach my $i (0..scalar(@surfs) - 1) {
	my $surf = $surfs[$i];
	while (my ($synid, $synonyms) = each %{$synos{$surf}->{synonyms}}) {
	    my $strs = qq(new Array\() . join (",", map {sprintf "\"%s\"", $_} @$synonyms) . qq(\));
	    my $initState = (exists $opt->{remove_synids}{$synid}) ? 0 : 1;
	    $jscode .= qq(termGroups[$i].push($initState, "$synid", $strs);\n);
	}
    }


    my %dpnds = ();
    foreach my $kihonku (@kihonkus) {
	my $kakarimoto = $kihonku;
	my $kakarisaki = $kihonku->parent;
	# 係り先がない場合は next
	next unless (defined $kakarisaki);

	# 並列句の処理１
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 日本->政治, 日本->経済 の部分
	my $buf = $kakarisaki;
	&generateDependencyTermsForParaType1(\%dpnds, $kakarimoto, $kakarisaki, \%tag2i);


	# 並列句の処理2
	# 日本の政治と経済を正す -> 日本->政治, 日本->経済. 政治->正す, 経済->正す のうち 政治->正す, 経済->正す の部分
	my $buf = $kakarimoto;
	while ($buf->dpndtype eq 'P' && defined $kakarisaki->parent) {
	    $buf = $kakarisaki;
	    $kakarisaki = $kakarisaki->parent;
	}
	# 係り受けオブジェクトの生成
	push (@{$dpnds{$tag2i{$kakarisaki}}}, &generateJavascriptCode4Dpnd($kakarimoto, $kakarisaki, \%tag2i));


	# クエリ解析により追加された係り受けオブジェクトの生成
	if ($kakarimoto->fstring() !~ /<クエリ削除係り受け>/ &&
	    $kakarisaki->fstring() =~ /<クエリ不要語>/ &&
	    $kakarisaki->fstring() !~ /<クエリ削除語>/ &&
	    $kakarisaki->fstring() !~ /<固有表現を修飾>/) {
	    my $_kakarisaki = $kakarisaki->parent();

	    # 係り先の係り先への係り受けを描画
	    if (defined $_kakarisaki) {
		push (@{$dpnds{$tag2i{$_kakarisaki}}}, &generateJavascriptCode4Dpnd($kakarimoto, $_kakarisaki, \%tag2i));
	    }
	}
    }

    # termGroup に係り受け関係を追加
    while (my ($i, $_dpnds) = each %dpnds) {
	$jscode .= qq(var dpnds$i = new Array \() . join (", ", @$_dpnds) . ");\n";
	$jscode .= qq(termGroups[$i].setDependancy(dpnds$i);\n);
    }

    # 表示する
    $jscode .= "setTermGroups(termGroups);\n";
    $jscode .= "paint(termGroups);\n";
    $jscode .= "}\n";
    $jscode .= "</script>\n";
    return $jscode;
}


sub getDrawingDependencyCodeForParaType1 {
    my ($kakarimoto, $kakarisaki, $i, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos) = @_;

    my $jscode;
    if (defined $kakarisaki && defined $kakarisaki->child) {
	foreach my $child ($kakarisaki->child) {
	    # 係り受け関係を追加する際、係り元のノード以前は無視する
	    # ex) 緑茶やピロリ菌
	    if ($child->dpndtype eq 'P' && $child->id > $kakarimoto->id) {
		my $mark = ($child->fstring() =~ /クエリ削除語/) ?  'Ｘ' : '△';
		$jscode .= &getDrawingDependencyCode($i, $kakarimoto, $child, $mark, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos);

		# 子の子についても処理する
		$jscode .= &getDrawingDependencyCodeForParaType1($kakarimoto, $child, $i, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos);
	    }
	}
    }
    return $jscode;
}


sub getDrawingDependencyCode {
    my ($i, $kakarimoto, $kakarisaki, $mark, $offsetX, $offsetY, $arrow_size, $font_size, $gid2num, $gid2pos) = @_;

    my $jscode = '';

    my $kakarimoto_gid = ($kakarimoto->synnodes)[0]->tagid;
    my $kakarisaki_gid = ($kakarisaki->synnodes)[0]->tagid;

    my $dist = abs($i - $gid2num->{$kakarisaki_gid});

    my $x1 = $gid2pos->{$kakarimoto_gid}->{pos} + (3 * $gid2pos->{$kakarimoto_gid}->{num_parent} * $arrow_size);
    my $x2 = $gid2pos->{$kakarisaki_gid}->{pos} - (3 * $gid2pos->{$kakarisaki_gid}->{num_child} * $arrow_size);
    $gid2pos->{$kakarimoto_gid}->{num_parent}++;
    $gid2pos->{$kakarisaki_gid}->{num_child}++;

    my $y = $offsetY - $font_size - (1.5 * $dist * $font_size);


    # 係り受けの線をひく

    if ($mark eq 'Ｘ') {
	$jscode .= qq(jg.setStroke(Stroke.DOTTED);\n);
    } else {
	$jscode .= qq(jg.setStroke(1);\n);
    }

    $jscode .= qq(jg.drawLine($x1, $offsetY, $x1, $y);\n);
    $jscode .= qq(jg.drawLine($x1 - 1, $offsetY, $x1 - 1, $y);\n);

    $jscode .= qq(jg.drawLine($x1, $y, $x2, $y);\n);
    $jscode .= qq(jg.drawLine($x1, $y - 1, $x2, $y - 1);\n);

    $jscode .= qq(jg.drawLine($x2, $y, $x2, $offsetY);\n);
    $jscode .= qq(jg.drawLine($x2 + 1, $y, $x2 + 1, $offsetY);\n);

    # 矢印
    $jscode .= qq(jg.fillPolygon(new Array($x2, $x2 + $arrow_size, $x2 - $arrow_size), new Array($offsetY, $offsetY - $arrow_size, $offsetY - $arrow_size));\n);


    # 線の上に必須・オプショナルのフラグを描画する
    $jscode .= qq(jg.drawStringRect(\'$mark\', $x1, $y - 1.05 * $font_size, $font_size, 'left');\n);

    return $jscode;
}


sub _getNormalizedString {
    my ($str) = @_;

    my ($yomi) = ($str =~ m!/(.+?)(?:v|a)?$!);
    $str =~ s/\[.+?\]//g;
    $str =~ s/(\/|:).+//;
    $str = lc($str);
    $str =~ s/人」/人/;

    return ($str, $yomi);
}

sub _pushbackBuf {
    my ($i, $tid2syns, $string, $yomi, $functional_word) = @_;

    foreach my $e (($string, $yomi)) {
	next unless ($e);

	$tid2syns->{$i}{$e} = 1;
	$tid2syns->{$i}{sprintf ("%s%s", $e, $functional_word)} = 1;
    }
}

sub _getPackedExpressions {
    my ($i, $synbuf, $tid2syns, $tids, $str, $functional_word, $syngraph) = @_;

    my %buf = ();
    my @synonymous_exps = split(/\|+/, decode('utf8', $syngraph->{syndb}{$str}));
    my $max_num_of_words = 0;
    if (scalar(@synonymous_exps) > 1) {
	foreach my $_string (@synonymous_exps) {
	    my ($string, $yomi) = &_getNormalizedString($_string);
	    &_pushbackBuf($i, $tid2syns, $string, undef, $functional_word);
	    $buf{$string} = 1;
	}

	foreach my $string (keys %buf) {
	    my $matched_exp = undef;
	    if (scalar(@$tids) > 1) {
		my $_string = $string;
		foreach my $tid (@$tids) {
		    my $isMatched = 0;
		    foreach my $_prev (sort {length($b) <=> length($a)} keys %{$tid2syns->{$tid}}) {
			if ($_string =~ /^$_prev/) {
			    $matched_exp .= $_prev;
			    $_string = "$'";
			    $isMatched = 1;
			    last;
			}
		    }

		    # 先行する語とマッチしなければ終了
		    last unless ($isMatched);
		}
	    }

	    unless ($matched_exp) {
		$synbuf->{$string} = 1;
	    } else {
		if ($string ne $matched_exp) {
		    $string =~ s/$matched_exp/（$matched_exp）/;
		    $synbuf->{$string} = 1;
		}
	    }
	    $max_num_of_words = length($string) if ($max_num_of_words < length($string));
	}
    }

    return $max_num_of_words;
}


# 同義グループに属す表現の取得と幅（文字数）の取得
sub _getExpressions {
    my ($termGroupID, $tag, $tid2syns, $syngraph, $opt) = @_;


    my $surf = ($tag->synnodes)[0]->midasi;
    my $surf_contentW = ($tag->mrph)[0]->midasi;
    my @repnames_contentW = ($tag->mrph)[0]->repnames;
    my $max_num_of_words = length($surf);
    my $functional_word = (($tag->mrph)[-1]->fstring !~ /<内容語>/) ? ($tag->mrph)[-1]->midasi : '';
    $functional_word =~ s!/.*$!!;

    my @basicNodes = ();
    my %synonyms = ();
    unless ($tag->fstring() =~ /<クエリ削除語>/) {
	foreach my $synnodes ($tag->synnodes) {
	    foreach my $node ($synnodes->synnode) {
		next if ($node->feature =~ /<上位語>/ || $node->feature =~ /<反義語>/ || $node->feature =~ /<否定>/);
		my %buf;

		# 基本ノードの獲得
		my $synid = $node->synid;
		if ($synid !~ /s\d+/) {
		    my ($_str, $_yomi) = &_getNormalizedString($synid);
		    push (@basicNodes, $_str);
		    push (@basicNodes, $_yomi) if ($_yomi);
		    &_pushbackBuf($termGroupID, $tid2syns, $_str, $_yomi, $functional_word);
		    next;
		}


		# 同義グループに属す表現の取得
		unless ($opt->{disable_synnode}) {
		    my @tids = $synnodes->tagids;
		    my $max_num_of_w = &_getPackedExpressions($termGroupID, \%buf, $tid2syns, \@tids, $synid, $functional_word, $syngraph);
		    $max_num_of_words = $max_num_of_w if ($max_num_of_words < $max_num_of_w);
		}


		# 出現形、基本ノードと同じ表現は削除する
		delete ($buf{$surf});
		delete ($buf{$surf_contentW});
		foreach my $basicNode (@basicNodes) {
		    delete ($buf{$basicNode});
		}
		foreach my $rep (@repnames_contentW) {
		    foreach my $word_w_yomi (split (/\?/, $rep)) {
			my ($hyouki, $yomi) = split (/\//, $word_w_yomi);
			delete ($buf{$hyouki});
		    }
		}

		foreach my $string (sort {$a cmp $b} keys %buf) {
		    push (@{$synonyms{$synid}}, $string);
		}
	    }
	}
    }

    return (\%synonyms, $max_num_of_words);
}

sub generateDependencyTermsForParaType1 {
    my ($dpnds, $kakarimoto, $kakarisaki, $tag2i) = @_;

    if (defined $kakarisaki->child) {
	foreach my $child ($kakarisaki->child) {

	    # 係り受け関係を追加する際、係り元のノード以前は無視する
	    # ex) 緑茶やピロリ菌
	    if ($child->dpndtype eq 'P' && $child->id > $kakarimoto->id) {
		push (@{$dpnds->{$tag2i->{$kakarisaki}}}, &generateJavascriptCode4Dpnd($kakarimoto, $child, $tag2i));

		# 子の子についても処理する
		&generateDependencyTermsForParaType1($dpnds, $kakarimoto, $child, $tag2i);
	    }
	}
    }
}

sub generateJavascriptCode4Dpnd {
    my ($kakarimoto, $kakarisaki, $tag2i) = @_;

    my $importance = 'OPTIONAL';
    $importance = 'NECCESARY'   if ($kakarimoto->fstring() =~ /クエリ必須係り受け/);
    $importance = 'UNNECCESARY' if ($kakarimoto->fstring() =~ /クエリ削除係り受け/ || $kakarisaki->fstring() =~ /クエリ削除語/);
    return sprintf ("new Dependancy(termGroups[%d], termGroups[%d], $importance)", $tag2i->{$kakarisaki}, $tag2i->{$kakarimoto});
}

1;
