package Renderer;

# $Id$

use strict;
use utf8;
use Encode;
use Configure;
use URI::Escape;

our $CONFIG = Configure::get_instance();

sub new {
    my($class) = @_;
    my $this = {};

    bless $this;
}

sub DESTROY {}

sub print_search_time {
    my ($this, $search_time, $hitcount, $params, $size, $keywords) = @_;

    $this->print_query($keywords);

    if ($hitcount < 1) {
	print ") を含む文書は見つかりませんでした。</DIV>";
    } else {
	# ヒット件数の表示
	print ") を含む文書が ${hitcount} 件見つかりました。</DIV>\n"; 

	# 検索にかかった時間を表示 (★cssに変更)
	printf("<div style=\"text-align:right;background-color:white;border-bottom: 0px solid gray;mergin-bottom:2em;\">%s: %3.1f [%s]</div>\n", encode('utf8', '検索時間'), $search_time, encode('utf8', '秒'));

	if ($hitcount > $params->{'results'}) {
	    print "スコアの上位" . ($params->{'start'} + 1) . "件目から" . $size . "件目までを表示しています。<BR></DIV>";
	} else {
	    print "</DIV>";
	}
    }
}

sub print_footer {
    my ($this, $params, $hitcount, $from) = @_;
    if ($hitcount > $params->{'results'}) {
	print "<DIV class='pagenavi'>検索結果ページ：";
	for (my $i = 0; $i < 10; $i++) {
	    my $offset = $i * $params->{'results'};
	    last if ($hitcount < $offset);
	    
	    if ($offset == $from) {
		print "<font color=\"brown\">" . ($i + 1) . "</font>&nbsp;";
	    } else {
		print "<a href=\"javascript:submit('$offset')\">" . ($i + 1) . "</a>&nbsp;";
	    }
	}
	print "</DIV>";
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

		    my $k_utf8 = encode('utf8', $mod_k);
		    if(exists($cbuff{$rep})){
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
	<link rel="stylesheet" type="text/css" href="http://nlpc06.ixnlp.nii.ac.jp/se.css">
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

    if ($params->{syngraph}) {
	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT><FONT color=black>同義表現を考慮する</FONT></LABEL></TD></TR>\n";
    } else {
	print "<TR><TD>オプション</TD><TD colspan=3 DIV style=\"text-align:left;\"><INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL><FONT color=black>同義表現を考慮する</FONT></LABEL></DIV></TD></TR>\n";
    }
    print "</TABLE>\n";
    
    print "</FORM>\n";

    print ("<FONT color='red'>$CONFIG->{MESSAGE}</FONT>\n") if ($CONFIG->{MESSAGE});

    print "</CENTER>";
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

sub printSearchResultForBrowserAccess {
    my ($this, $params, $result, $query, $from, $end, $hitcount, $color) = @_;

    $this->print_search_time(0, $hitcount, $params, 10, $query->{keywords});

    my $uri_escaped_search_keys = $this->get_uri_escaped_query($query);

    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	my $score = $result->[$rank]{score_total};
	my $snippet = $result->[$rank]{snippets};

	my $output = "<DIV class=\"result\">";
	$score = sprintf("%.4f", $score);
	$output .= "<SPAN class=\"rank\">" . ($rank + 1) . "</SPAN>";
	$output .= "<A class=\"title\" href=index.cgi?cache=$did&KEYS=" . $uri_escaped_search_keys . " target=\"_blank\" class=\"ex\">";
	$output .= $result->[$rank]{title} . "</a>";
	my $num_of_sim_pages = 0;
	$num_of_sim_pages = scalar(@{$result->[$rank]{similar_pages}}) if (defined $result->[$rank]{similar_pages});
	if (defined $num_of_sim_pages && $num_of_sim_pages > 0) {
	    my $open_label = "類似ページを表示 ($num_of_sim_pages 件)";
	    my $close_label = "類似ページを非表示 ($num_of_sim_pages 件)";
	    $output .= encode('utf8', "<DIV class=\"meta\">id=$did, score=$score, <A href=\"javascript:void(0);\" onclick=\"toggle_simpage_view('simpages_$rank', this, '$open_label', '$close_label');\">$open_label</A> </DIV>\n");
	} else {
	    $output .= "<DIV class=\"meta\">id=$did, score=$score</DIV>\n";
	}
	$output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
	$output .= "<A class=\"cache\" href=\"$result->[$rank]{url}\" target=\"_blank\">$result->[$rank]{url}</A>\n";
	$output .= "</DIV>";

	$output .= "<DIV id=\"simpages_$rank\" style=\"display: none;\">";
	foreach my $sim_page (@{$result->[$rank]{similar_pages}}) {
	    my $did = sprintf("%09d", $sim_page->{did});
 	    my $score = $sim_page->{score_total};

 	    # 装飾されたスニペッツの取得
	    my $snippet = $result->[$rank]{snippets};
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
}

1;
