package Renderer;

# $Id$

use strict;
use utf8;
use Encode;
use Configure;
use POSIX qw(strftime);
use URI::Escape;
use XML::Writer;

our $CONFIG = Configure::get_instance();

sub new {
    my($class, $called_from_API) = @_;
    my $this = {
	called_from_API => $called_from_API
    };

    bless $this;
}

sub DESTROY {}

sub print_search_time {
    my ($this, $search_time, $hitcount, $params, $size, $keywords) = @_;

    $this->{q2color} = $this->print_query($keywords);

    if ($hitcount < 1) {
	print ") を含む文書は見つかりませんでした。</DIV>";
    } else {
	# ヒット件数の表示
	print ") を含む文書が ${hitcount} 件見つかりました。\n"; 
	if ($size > $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}) {
	    my $end = $params->{'start'} + $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'};
	    $end = $size if ($end > $size);
	    printf("スコアの上位%d件目から%d件目までを表示しています。<BR></DIV>", $params->{'start'} + 1, $end);
	} else {
	    print "</DIV>";
	}
	# 検索にかかった時間を表示 (★cssに変更)
	printf("<div style=\"text-align:right;background-color:white;border-bottom: 0px solid gray;mergin-bottom:2em;\">%s: %3.1f [%s]</div>\n", "検索時間", $search_time, "秒");
    }
}

sub printFooter {
    my ($this, $params, $hitcount, $current_page, $size) = @_;

    my $last_page_flag = 0;
    if ($hitcount >= $params->{'results'}) {
	print "<DIV class='pagenavi'>検索結果ページ：";
	for (my $i = 0; $i < $CONFIG->{'NUM_OF_SEARCH_RESULTS'} / $CONFIG->{'NUM_OF_RESULTS_PER_PAGE'}; $i++) {
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
		print "<a href=\"javascript:submit('$offset')\">" . ($i + 1) . "</a>&nbsp;";
	    }
	}
	print "</DIV>";
    }

    printf("<DIV class=\"bottom_message\">上の%d件と類似したページは除外されています。</DIV>\n", $size) if ($last_page_flag && $size < $hitcount && $size < $CONFIG->{'NUM_OF_SEARCH_RESULTS'});


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
    ご意見は tsubaki あっと nlp.kyoto-u.ac.jp までお願い致します。
    <P>
    <DIV><B>&copy;2006 - 2008 黒橋研究室</B></DIV> 
    </DIV>
    </body>
    </html>
END_OF_HTML
}

sub print_query {
    my($this, $keywords) = @_;

    my %cbuff = ();
    my $color = 0;
    print "<DIV style=\"padding: 0.25em 1em; background-color:#f1f4ff;border-top: 1px solid gray;border-bottom: 1px solid gray;mergin-left:0px;\">検索キーワード (";

    my %syndb;
    foreach my $qk (@{$keywords}){
	if ($qk->{is_phrasal_search} > 0 && $qk->{sentence_flag} < 0) {
	    printf("<b style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$qk->{rawstring}</b>");
	} else {
	    my $words = $qk->{words};
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}){
		foreach my $rep (sort {$b->{string} cmp $a->{string}} @{$reps}){
		    next if ($rep->{isContentWord} < 1 && $qk->{is_phrasal_search} < 1);

		    my $tips;
		    my $mod_k = $rep->{string};
		    if ($mod_k =~ /s\d+:/) {
			unless (defined %syndb) {
			    tie %syndb, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . "<br>\n";
			}

			foreach my $synonym (split('\|', $syndb{$mod_k})) {
			    if($synonym =~ m!^([^/]+)/!){
				$synonym = $1;
			    }
			    $synonym =~ s/<[^>]+>//g;
			    $tips .= ($synonym . ",");
			}
			chop($tips);

			$mod_k =~ s/s\d+://g;
			$mod_k = "&lt;$mod_k&gt;";
		    }

		    my $k_utf8 = $mod_k;
		    if(exists($cbuff{$rep->{string}})){
			printf("<span title=\"$tips\" style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$rep->{string}}->{foreground}, $cbuff{$rep->{string}}->{background});
		    }else{
			if($color > 4){
			    print "<span title=\"$tips\" style=\"color:white;margin:0.1em 0.25em;background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'white';
			    $cbuff{$rep->{string}}->{background} = "#$CONFIG->{HIGHLIGHT_COLOR}[$color]";
			}else{
			    print "<span title=\"$tips\" style=\"margin:0.1em 0.25em;background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'black';
			    $cbuff{$rep->{string}}->{background} = "#$CONFIG->{HIGHLIGHT_COLOR}[$color]";
			}
			$color = (++$color%scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
		    }
		}
	    }
	    
	    my $dpnds = $qk->{dpnds};
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

    if (defined %syndb) {
	untie %syndb;
    }

    return \%cbuff;
}

sub print_tsubaki_interface {
    my ($this, $params) = @_;
    print << "END_OF_HTML";
    <html>
	<head>
	<title>情報爆発プロジェクト 検索エンジン基盤 TSUBAKI</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="./se.css">
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

    # タイトル出力
print "<DIV style=\"text-align:right;margin:0.5em 1em 0em 0em;\"><A href=\"http://tsubaki-wiki.ixnlp.nii.ac.jp/\">TSUBAKI Wiki はこちら</A><BR></DIV>\n";
    print "<TABLE><TR><TD valign=top>\n";
    printf ("<A href=%s><IMG border=0 src=./logo.png></A><P>\n", $CONFIG->{INDEX_CGI});
    print "</TD><TD>";

    # フォーム出力
    print "<FORM name=\"search\" method=\"post\" action=\"\" enctype=\"multipart/form-data\">\n";
    print "<INPUT type=\"hidden\" name=\"start\" value=\"0\">\n";
    print "<INPUT type=\"text\" name=\"INPUT\" value=\'$params->{'query'}\'/ size=\"90\">\n";
    print "<INPUT type=\"submit\"name=\"送信\" value=\"検索する\"/>\n";
    print "<INPUT type=\"button\"name=\"clear\" value=\"クリア\" onclick=\"document.all.INPUT.value=''\"/>\n";

    print "<TABLE style=\"border=0px solid silver;padding: 0.25em;margin: 0.25em;\"><TR><TD>検索条件</TD>\n";
    if($params->{'logical_operator'} eq "OR"){
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/>全ての語を含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>いずれかの語を含む</LABEL></TD>\n";
    }elsif($params->{'logical_operator'} eq "AND"){
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

    if ($CONFIG->{DISABLE_SYNGRAPH_SEARCH}) {
	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" disabled></INPUT><FONT color=silver>同義表現を考慮する</FONT></LABEL></TD></TR>\n";
    } else {
	if ($params->{syngraph}) {
	    print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT><FONT color=black>同義表現を考慮する</FONT></LABEL></TD></TR>\n";
	} else {
	    print "<TR><TD>オプション</TD><TD colspan=3 DIV style=\"text-align:left;\"><INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL><FONT color=black>同義表現を考慮する</FONT></LABEL></DIV></TD></TR>\n";
	}
    }

    print "</TABLE>\n";
    
    print "</FORM>\n";

    print "</TD></TR></TABLE>\n";

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
	<link rel="stylesheet" type="text/css" href="./se.css">
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

    # タイトル出力
print "<DIV style=\"text-align:right;margin:0.5em 1em 0em 0em;\"><A href=\"http://tsubaki-wiki.ixnlp.nii.ac.jp/\">TSUBAKI Wiki はこちら</A><BR></DIV>\n";
    print "<CENTER style='maring:1em; padding:1em;'>";
    printf ("<A href=%s><IMG border=0 src=./logo.png></A><P>\n", $CONFIG->{INDEX_CGI});
    # フォーム出力
    print "<FORM name=\"search\" method=\"post\" action=\"\" enctype=\"multipart/form-data\">\n";
    print "<INPUT type=\"hidden\" name=\"start\" value=\"0\">\n";
    print "<INPUT type=\"text\" name=\"INPUT\" value=\'$params->{'query'}\'/ size=\"90\">\n";
    print "<INPUT type=\"submit\"name=\"送信\" value=\"検索する\"/>\n";
    print "<INPUT type=\"button\"name=\"clear\" value=\"クリア\" onclick=\"document.all.INPUT.value=''\"/>\n";

    print "<TABLE style=\"border=0px solid silver;padding: 0.25em;margin: 0.25em;\"><TR><TD>検索条件</TD>\n";
    if($params->{'logical_operator'} eq "OR"){
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/>全ての語を含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>いずれかの語を含む</LABEL></TD>\n";
    }elsif($params->{'logical_operator'} eq "AND"){
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

    if ($CONFIG->{DISABLE_SYNGRAPH_SEARCH}) {
	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" disabled></INPUT><FONT color=lightGray>同義表現を考慮する</FONT></LABEL></TD></TR>\n";
    } else {
	if ($params->{syngraph}) {
	    print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT><FONT color=black>同義表現を考慮する</FONT></LABEL></TD></TR>\n";
	} else {
	    print "<TR><TD>オプション</TD><TD colspan=3 DIV style=\"text-align:left;\"><INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL><FONT color=black>同義表現を考慮する</FONT></LABEL></DIV></TD></TR>\n";
	}
    }

    print "</TABLE>\n";
    
    print "</FORM>\n";

    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});

    print "</CENTER>";

    # フッターの表示
    $this->printFooter($params, 0, 0, 0);
}

sub get_uri_escaped_query {
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

    # キャッシュページで索引語をハイライトさせるため、索引語をuri_escapeした文字列を生成する
    my $search_k;
    foreach my $qk (@{$query->{keywords}}) {
	my $words = $qk->{words};
	foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @$words) {
	    foreach my $rep (sort {$b->{string} cmp $a->{string}} @$reps) {
		next if ($rep->{isContentWord} < 1 && $rep->{is_phrasal_search} < 1);
		my $string = $rep->{string};

		$string =~ s/s\d+://; # SynID の削除
		$string =~ s/\/.+$//; # 読みがなの削除
		$search_k .= "$string:";
	    }
	}
    }
    chop($search_k);
    my $uri_escaped_search_keys = &uri_escape(encode('utf8', $search_k));


    # スニペット生成のため、類似ページも含め、表示されるページのIDを取得
    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	push(@{$query->{dids}}, $did);
	unless ($this->{called_from_API}) {
	    foreach my $sim_page (@{$result->[$rank]{similar_pages}}) {
		my $did = sprintf("%09d", $sim_page->{did});
		push(@{$query->{dids}}, $did);
	    }
	}
    }

    my $sni_obj = new SnippetMakerAgent();
    $sni_obj->create_snippets($query, $query->{dids}, {discard_title => 1, syngraph => $opt->{'syngraph'}, window_size => 5});

    # 装飾されたスニペッツを取得
    my $did2snippets = ($this->{called_from_API}) ? $sni_obj->get_snippets_for_each_did() : $sni_obj->get_decorated_snippets_for_each_did($query, $this->{q2color});
    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	$result->[$rank]{snippets} = $did2snippets->{$did};
    }
}

sub printSearchResultForBrowserAccess {
    my ($this, $params, $results, $query, $logger, $color) = @_;

    ##########################
    # ロゴ、検索フォームの表示
    ##########################
    $this->print_tsubaki_interface($params);


    my $size = scalar(@$results);
    my $start = $params->{start};
    my $end = ($start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE} > $size) ? $size : $start + $CONFIG->{NUM_OF_RESULTS_PER_PAGE};


    ############################
    # 検索クエリ、検索時間の表示
    ############################
    $this->print_search_time($logger->getParameter('search'), $logger->getParameter('hitcount'), $params, $size, $query->{keywords});



    ############################
    # 必要ならばスニペットを生成
    ############################
    unless ($params->{no_snippets}) {
	# 検索結果（表示分）についてスニペットを生成
	$this->get_snippets($params, $results, $query, $start, $end);
    }
    # スニペット生成に要した時間をロギング
    $logger->setTimeAs('snippet_creation', '%.3f');



    ################
    # 検索結果を表示
    ################
    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);
    for (my $rank = $start; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $results->[$rank]{did});
	my $score = $results->[$rank]{score_total};
	my $snippet = $results->[$rank]{snippets};

	my $output = "<DIV class=\"result\">";
	$score = sprintf("%.4f", $score);
	$output .= "<SPAN class=\"rank\">" . ($rank + 1) . "</SPAN>";
	$output .= "<A class=\"title\" href=index.cgi?cache=$did&KEYS=" . $uri_escaped_search_keys . " target=\"_blank\" class=\"ex\">";
	$output .= $results->[$rank]{title} . "</a>";
	my $num_of_sim_pages = 0;
	$num_of_sim_pages = scalar(@{$results->[$rank]{similar_pages}}) if (defined $results->[$rank]{similar_pages});
	if (defined $num_of_sim_pages && $num_of_sim_pages > 0) {
	    my $open_label = "類似ページを表示 ($num_of_sim_pages 件)";
	    my $close_label = "類似ページを非表示 ($num_of_sim_pages 件)";
	    $output .= "<DIV class=\"meta\">id=$did, score=$score, <A href=\"javascript:void(0);\" onclick=\"toggle_simpage_view('simpages_$rank', this, '$open_label', '$close_label');\">$open_label</A> </DIV>\n";
	} else {
	    $output .= "<DIV class=\"meta\">id=$did, score=$score</DIV>\n";
	}
	$output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
	$output .= "<A class=\"cache\" href=\"$results->[$rank]{url}\" target=\"_blank\">$results->[$rank]{url}</A>\n";
	$output .= "</DIV>";

	$output .= "<DIV id=\"simpages_$rank\" style=\"display: none;\">";
	foreach my $sim_page (@{$results->[$rank]{similar_pages}}) {
	    my $did = sprintf("%09d", $sim_page->{did});
 	    my $score = $sim_page->{score_total};

 	    # 装飾されたスニペッツの取得
	    my $snippet = $results->[$rank]{snippets};
 	    $score = sprintf("%.4f", $score);

 	    $output .= "<DIV class=\"similar\">";
 	    $output .= "<A class=\"title\" href=index.cgi?cache=$did&KEYS=" . $uri_escaped_search_keys . " target=\"_blank\" class=\"ex\">";
 	    $output .= $sim_page->{title} . "</a>";
 	    $output .= "<DIV class=\"meta\">id=$did, score=$score</DIV>\n";
 	    $output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
 	    $output .= "<A class=\"cache\" href=\"$sim_page->{url}\">$sim_page->{url}</A>\n";
 	    $output .= "</DIV>";
	}
	$output .= "</DIV>\n";

	# 1 ページ分の結果を表示
	print $output;
    }

    # フッターの表示
    $this->printFooter($params, $logger->getParameter('hitcount'), $start, $size);

    # 表示に要した時間のロギング
    $logger->setTimeAs('print_result', '%.3f');
}

sub printRequestResult {
    my ($this, $dids, $results, $requestItems) = @_;
    # 出力
    my $date = `date +%m%d-%H%M%S`; chomp ($date);
    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    $writer->startTag('DocInfo',
		      time => $date,
		      result_items => join(':', sort {$b cmp $a} keys %$requestItems));
    foreach my $did (@$dids) {
	&printResult($writer, $did, $results->{$did});
    }
    $writer->endTag('DocInfo');
}

# 検索結果に含まれる１文書を出力
sub printResult {
    my ($writer, $did, $results) = @_;

    $writer->startTag('Result', Id => sprintf("%09d", $did));
    foreach my $itemName (sort {$b cmp $a} keys %$results) {
	$writer->startTag($itemName);
	if ($itemName ne 'Cache') {
	    $writer->characters($results->{$itemName}. "\n");
	} else {
	    $writer->startTag('Url');
	    $writer->characters($results->{Cache}{URL});
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters($results->{Cache}{Size});
	    $writer->endTag('Size');
	}
	$writer->endTag($itemName);
    }
    $writer->endTag('Result');
}


sub printSearchResultForAPICall {
    my ($this, $params, $result, $query, $from, $end, $hitcount) = @_;

    my $did2snippets = {};
    if ($params->{no_snippets} < 1 || $params->{Snippet} > 0) {
	my @dids = ();
	for (my $rank = $from; $rank < $end; $rank++) {
	    push(@dids, sprintf("%09d", $result->[$rank]{did}));
	}
	my $sni_obj = new SnippetMakerAgent();
	$sni_obj->create_snippets($query, \@dids, {discard_title => 0, syngraph => $params->{'syngraph'}, window_size => 5});
	$did2snippets = $sni_obj->get_snippets_for_each_did();
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
	    $writer->startTag('Snippet');
	    $writer->characters($did2snippets->{$did});
	    $writer->endTag('Snippet');
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
