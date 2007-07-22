#!/home/skeiji/local/bin/perl
#!/usr/bin/env perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use Encode;
use utf8;

use Time::HiRes;
use CDB_File;

use SearchEngine;
use QueryParser;
use SnippetMaker;

## 定数
# my $INDEX_DIR = '/home/skeiji/cvs/SearchEngine/scripts/tmp/SearchEngine/scripts/test_set/syn_small';
my $INDEX_DIR = '/work/skeiji/dat';
my $INDEX_DIR2 = '/work/skeiji/dat/xmls';
my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", "880000", "00aa00", "886800", "004699", "990099");
my $PORT = 99557;
my $TOOL_HOME='/home/skeiji/local/bin';
my @HOSTS;
for(my $i = 161; $i < 192; $i++){
    next if ($i == 188);
    next if ($i == 187);
    next if ($i == 186);
    push(@HOSTS,   "157.1.128.$i");
}

my $cgi = new CGI;
my %params = ();
## 検索条件の初期化
$params{'start'} = 0;
$params{'logical_operator'} = 'WORD_AND';
$params{'dpnd'} = 1;
$params{'results'} = 50;
$params{'force_dpnd'} = 0;
$params{'filter_simpages'} = 0;
$params{'near'} = 0;
$params{'syngraph'} = 0;

## 指定された検索条件に変更
$params{'URL'} = $cgi->param('URL') if($cgi->param('URL'));
$params{'query'} = decode('utf8', $cgi->param('INPUT')) if($cgi->param('INPUT'));
if($params{'query'}){
    $params{'start'} = $cgi->param('start') if(defined($cgi->param('start')));
    $params{'logical_operator'} = $cgi->param('logical') if(defined($cgi->param('logical')));
}

if($params{'logical_operator'} eq 'DPND_AND'){
    $params{'force_dpnd'} = 1;
    $params{'dpnd'} = 1;
    $params{'logical_operator'} = 'AND';
}else{
    if($params{'logical_operator'} eq 'WORD_AND'){
	$params{'logical_operator'} = 'AND';
    }
    $params{'force_dpnd'} = 0;
    $params{'dpnd'} = 1;
}

if($cgi->param('filter_simpages') == 1){
    $params{'filter_simpages'} = 1;
}else{
    $params{'filter_simpages'} = 0;
}

$params{'near'} = shift(@{$cgi->{'near'}}) if ($cgi->param('near'));
$params{'syngraph'} = 1 if ($cgi->param('syngraph'));
$params{'only_hitcount'} = undef;


# HTTPヘッダ出力
print header(-charset => 'utf-8');



# 指定されたＵＲＬの表示       
if ($params{'URL'}) {
    my $color;
    my $html = '';
    if(-e $params{'URL'}){
	$html = `$TOOL_HOME/nkf -w $params{'URL'}`;
    }else{
	my $newurl = $params{'URL'} . ".gz";
	$html = `gunzip -c  $newurl | $TOOL_HOME/nkf -w`;
    }
    $html = decode('utf8', $html);
    $html =~ s/charset=//i;

    # KEYごとに色を付ける
    my @KEYS = split(/:/, decode('utf8', $cgi->param('KEYS')));
    print "<DIV style=\"padding:1em; background-color:#f1f4ff; border-top:1px solid gray; border-bottom:1px solid gray;\"><U>次のキーワードがハイライトされています:&nbsp;";
    for my $key (@KEYS) {
	next unless ($key);
#	next if($key =~ /\->/);

	print "<span style=\"background-color:#$COLOR[$color];\">";
	print encode('utf8', $key) . "</span>&nbsp;";
	if($color > 4){
	    $html =~ s/$key/<span style="color:white; background-color:#$COLOR[$color];">$key<\/span>/g;
	}else{
	    $html =~ s/$key/<span style="background-color:#$COLOR[$color];">$key<\/span>/g;
	}
	$color = (++$color%scalar(@COLOR));
    }
    print "</U></DIV>";
    print encode('utf8', $html);
}

else {
    # HTML出力
    &printSearchInterface();

    # 入力があった場合
    if($params{query}){
	# parse query
	my $start_time_genuine = Time::HiRes::time;

	my $q_parser = new QueryParser({
	    KNP_PATH => "/home/skeiji/local/bin",
	    JUMAN_PATH => "/home/skeiji/local/bin",
	    SYNDB_PATH => "/home/skeiji/SynGraph/syndb/i686",
	    KNP_OPTIONS => ['-postprocess','-tab'] });

	$q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;
	
	# logical_cond_qk  クエリ間の論理演算
	my $query = $q_parser->parse($params{query}, {logical_cond_qk => $params{logical_operator}, syngraph => $params{syngraph}});
	$query->{results} = $params{results};
 	foreach my $qk (@{$query->{keywords}}) {
	    $qk->{force_dpnd} = 1 if ($params{force_dpnd});
	    $qk->{logical_cond_qkw} = 'OR' if ($params{logical_operator} eq 'OR');
	}
	
	my $se_obj = new SearchEngine($params{syngraph});
	if ($params{syngraph} > 0) {
	    $se_obj->init('/data/idx_syn/dfdbs');
	} else {
	    $se_obj->init('/var/www/cgi-bin/dbs/dfdbs');
	}

	my $start_time = Time::HiRes::time;
	my ($hitcount, $results) = $se_obj->search($query);
	my $finish_time = Time::HiRes::time;
	my $search_time = $finish_time - $start_time;

	# 検索クエリの表示
	my $cbuff = &printQueries($query->{keywords});

	if ($hitcount < 1) {
	    print ") を含む文書は見つかりませんでした。</DIV>";
	} else {
 	    # 検索結果の表示
 	    my $output;
 	    my $until = $params{'start'} + $params{'results'};
 	    $until = $hitcount if($hitcount < $until);
 	    $params{'results'} = $hitcount if($params{'results'} > $hitcount);

  	    print ") を含む文書が ${hitcount} 件見つかりました。"; 
#  	    print ") を含む文書が ${hitcount} 件見つかりました。<BR>"; 
	    if($hitcount > $params{'results'}){
		print "スコアの上位" . ($params{'start'} + 1) . "件目から" . $until . "件目までを表示しています。<BR></DIV>";
	    }else{
		print "</DIV>";
	    }

	    my $start_time = Time::HiRes::time;
 	    ## merging
 	    my $max = 0;
 	    my @merged_results;
 	    while ($until > scalar(@merged_results)) {
 		for (my $k = 0; $k < scalar(@{$results}); $k++) {
 		    next unless (defined($results->[$k][0]));

 		    if ($results->[$max][0]{score} <= $results->[$k][0]{score}) {
 			$max = $k;
 		    }
 		}
 		push(@merged_results, shift(@{$results->[$max]}));
 	    }
	    my $finish_time = Time::HiRes::time;
	    my $merge_time = $finish_time - $start_time;

 	    printf("<div style=\"text-align:right;background-color:white;border-bottom: 0px solid gray;mergin-bottom:2em;\"><font color=\"white\">%3.3f</font> %s: %3.3f [%s]</div>\n", $merge_time, encode('utf8', '検索時間'), $search_time, encode('utf8', '秒'));

 	    # ログの保存
	    my $date = `date +%m%d-%H%M%S`; chomp ($date);
 	    open(OUT, ">> /se_tmp/input.log");
	    my $param_str;
	    foreach my $k (sort keys %params){
		$param_str .= "$k=$params{$k},";
	    }
	    $param_str .= "hitcount=$hitcount,time=$search_time";
 	    print OUT "$date $ENV{REMOTE_ADDR} SEARCH $param_str\n";
 	    close(OUT);

	    my $search_k;
	    foreach my $qk (@{$query->{keywords}}) {
		my $words = $qk->{words};
		foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}) {
		    foreach my $rep (@{$reps}) {
			next if($rep->{isContentWord} < 1 && $rep->{near} < 1);
			my $string = $rep->{string};

			$string =~ s/s\d+://; # SynID の削除
			$string =~ s/\/.+$//; # 読みがなの削除
			$search_k .= "$string:";
		    }
		}
	    }
	    chop($search_k);
	    
	    $params{'query'} =~ s/\s/:/g;
	    $params{'query'} =~ s/　/:/g;
	    my %urldbs = ();
	    my $dbfp = "/var/www/cgi-bin/dbs/title.cdb";
	    tie my %titledb, 'CDB_File', $dbfp or die "$0: can't tie to $dbfp $!\n";
	    my $prev_page = {title => undef, url => undef, snippets => undef, score => 0};
	    for(my $rank = $params{'start'}; $rank < scalar(@merged_results); $rank++){
		my $did = $merged_results[$rank]->{did};
		my $score =  $merged_results[$rank]->{score};
		my $url = sprintf("/net2/nlpcf34/disk02/skeiji/htmls/%02d/h%04d/%08d.html", $did / 1000000, $did / 10000, $did);
		my $htmlpath = $url;

		## snippet用に重要文を抽出
		my $sentences;
		if ($params{'syngraph'}) {
#		    my $xmlpath = sprintf("$INDEX_DIR/x%04d/%08d.xml", $did / 10000, $did);
		    my $xmlpath = sprintf("/net2/nlpcf34/disk07/skeiji/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
		    $sentences = &SnippetMaker::extractSentencefromSynGraphResult($query->{keywords}, $xmlpath);
		} else {
		    my $filepath = sprintf("/net/nlpcf2/export2/skeiji/data/xmls/x%04d/%08d.xml", $did / 10000, $did);
		    unless (-e $filepath || -e "$filepath.gz") {
			$filepath = sprintf("/net2/nlpcf34/disk02/skeiji/xmls/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
		    }
		    $sentences = &SnippetMaker::extractSentencefromKnpResult($query->{keywords}, $filepath);
		}

		# ハイライトされたスニペッツの生成
 		my $snippet;
		my $wordcnt = 0;
 		foreach my $sentence (sort {$b->{score} <=> $a->{score}} @{$sentences}) {
		    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
			my $highlighted = -1;
			my $surf = $sentence->{surfs}[$i];
 			foreach my $rep (@{$sentence->{reps}[$i]}) {
 			    if (exists($cbuff->{$rep})) {
 				$snippet .= sprintf("<span style=\"color:%s;margin:0.1em 0.25em;background-color:%s;\">%s<\/span>", $cbuff->{$rep}->{foreground}, $cbuff->{$rep}->{background}, $surf);
 				$highlighted = 1;
 			    }
			    last if ($highlighted > 0);
 			}
			$snippet .= $surf if ($highlighted < 0);
			$wordcnt++;
			
			if ($wordcnt > 100) {
			    $snippet .= " <b>...</b>";
			    last;
			}
		    }
		    # ★ 多重 foreach の脱出に label をつかうこと
		    last if ($wordcnt > 100);
		}

		# フレーズの強調表示
 		foreach my $qk (@{$query->{keywords}}){
 		    next unless ($qk->{near} == 0);
 		    $snippet =~ s!$qk->{rawstring}!<b>$qk->{rawstring}</b>!g;
 		}

 		$snippet = encode('utf8', $snippet) if (utf8::is_utf8($snippet));

  		$did = sprintf("%08d", $did);
 		my $htmltitle = 'no title';
 		$htmltitle = decode('euc-jp', $titledb{$did}) if (exists($titledb{$did}));
		$htmltitle =~ s/(.{30}).*/\1 <B>\.\.\.<\/B>/ if (length($htmltitle) > 30);

 		my $did_prefix = sprintf("%02d", $did / 1000000);
		my $url = $urldbs{$did_prefix}->{$did};
 		unless (defined($url)) {
 		    my $urldbfp = "/var/www/cgi-bin/dbs/$did_prefix.url.cdb";
 		    tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
 		    $urldbs{$did_prefix} = \%urldb;
 		    $url = $urldb{$did};
 		}

  		my $output = "<DIV class=\"result\">";
		if ($prev_page->{title} eq $htmltitle && $prev_page->{score} == $score) {
		    next if ($params{'filter_simpages'});

		    $output = "<DIV class=\"similar\">";
		} else {
		    my $sim = 0;
# 		    if(defined($prev_page->{words})){
# 			$sim = &calculateSimilarity($prev_page->{words}, \%words);
# 		    }
# 		    if($sim > 0.9){
# 			$output = "<DIV class=\"similar\">";
# 		    }

# 		    $prev_page->{words} = \%words;
# 		    $prev_page->{title} = $htmltitle;
# 		    $prev_page->{score} = $score;

# 		    if($params{'filter_simpages'} && $sim > 0.9){
# 			next;
# 		    }
		}

 		$score = sprintf("%.4f", $score);
 		$output .= "<SPAN class=\"rank\">" . ($rank + 1) . "</SPAN>";
 		$output .= "<A class=\"title\" href=index.cgi?URL=$htmlpath&KEYS=" . &uri_escape(encode('utf8', $search_k)) . " target=\"_blank\" class=\"ex\">";
 		$output .= encode('utf8', $htmltitle) . "</a>";
 		$output .= "<DIV class=\"meta\">id=$did, score=$score</DIV>\n";
 		$output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
		$output .= "<A class=\"cache\" href=\"$url\">$url</A>\n";
 		$output .= "</DIV>";
 		print $output;
 	    }

	    foreach my $k (keys %urldbs){
 		untie %{$urldbs{$k}};
 	    }
 	    untie %titledb;
	    
 	    if($hitcount > $params{'results'}){
 		print "<DIV class='pagenavi'>検索結果ページ：";
 		for(my $i = 0; $i < 10; $i++){
 		    my $offset = $i * $params{'results'};
 		    last if($hitcount < $offset);
		    
 		    if($offset == $params{'start'}){
 			print "<font color=\"brown\">" . ($i + 1) . "</font>&nbsp;";
 		    }else{
 			print "<a href=\"javascript:submit('$offset')\">" . ($i + 1) . "</a>&nbsp;";
 		    }
 		}
 		print "</DIV>";
 	    }
 	}
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

    <DIV class="footer">&copy;2007 黒橋研究室</DIV>
    </body>
    </html>
END_OF_HTML
}    

sub norm {
    my ($v) = @_;
    my $norm = 0;
    foreach my $k (keys %{$v}){
	$norm += ($v->{$k}**2);
    }
    return sqrt($norm);
}

sub calculateSimilarity {
    my ($v1, $v2) = @_;
    my $size1 = scalar(keys %{$v1});
    my $size2 = scalar(keys %{$v2});
    if($size1 > $size2){
	return calculateSimilarity($v2, $v1);
    }

    my $sim = 0;
    foreach my $k (keys %{$v1}){
	next unless(exists($v2->{$k}));
	$sim += ($v1->{$k} * $v2->{$k});
    }

    my $bunbo = &norm($v1) * &norm($v2);
    if($bunbo == 0){
	return 0;
    }else{
	return ($sim / $bunbo);
    }
}

sub printQueries {
    my($keywords) = @_;

    my %cbuff = ();
    my $color = 0;
    print "<DIV style=\"padding: 0.25em 1em; background-color:#f1f4ff;border-top: 1px solid gray;border-bottom: 1px solid gray;mergin-left:0px;\">検索キーワード (";

    foreach my $qk (@{$keywords}){
	if ($qk->{near} == 0 && $qk->{sentence_flag} < 0) {
	    printf("<b style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$qk->{rawstring}</b>");
	} else {
	    my $words = $qk->{words};
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}){
		foreach my $rep (@{$reps}){
		    next if($rep->{isContentWord} < 1 && $qk->{near} < 1);

		    my $k_utf8 = encode('utf8', $rep->{string});
		    if(exists($cbuff{$rep})){
			printf("<span style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$rep->{string}}->{foreground}, $cbuff{$rep->{string}}->{background});
		    }else{
			if($color > 4){
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'white';
			    $cbuff{$rep->{string}}->{background} = "#$COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'black';
			    $cbuff{$rep->{string}}->{background} = "#$COLOR[$color]";
			}
			$color = (++$color%scalar(@COLOR));
		    }
		}
	    }
	    
	    my $dpnds = $qk->{dpnds};
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$dpnds}){
		foreach my $rep (@{$reps}){
		    my $k_tmp  = $rep->{string};
		    $k_tmp =~ s/->/→/;
		    my $k_utf8 = encode('utf8', $k_tmp);
		    if(exists($cbuff{$rep->{string}})){
			printf("<span style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$rep->{string}}->{foreground}, $cbuff{$rep->{string}}->{background});
		    }else{
			if($color > 4){
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'white';
			    $cbuff{$rep->{string}}->{background} = "#$COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'black';
			    $cbuff{$rep->{string}}->{background} = "#$COLOR[$color]";
			}
			$color = (++$color%scalar(@COLOR));
		    }
		}
	    }
	}
    }

    return \%cbuff;
}

sub printSearchInterface{
    print << "END_OF_HTML";
    <html>
	<head>
	<title>検索エンジン基盤 TSUBAKI</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="./se.css">
	</head>
	<body style="margin:0em;">
END_OF_HTML

    # タイトル出力
print "<DIV style=\"text-align:right;margin:0.5em 1em 0em 0em;\"><A href=\"api.html\">APIの使い方</A></DIV>\n";
    print "<CENTER style='maring:1em; padding:1em;'>";
    print "<A href='http://tsubaki.ixnlp.nii.ac.jp/index.cgi'><IMG border=0 src=logo.png></A><P>\n";
    # フォーム出力
    print "<FORM name=\"search\" method=\"post\" action=\"\" enctype=\"multipart/form-data\">\n";
    print "<INPUT type=\"hidden\" name=\"start\" value=\"0\">\n";
    print "<INPUT type=\"text\" name=\"INPUT\" value=\'$params{'query'}\'/ size=\"90\">\n";
    print "<INPUT type=\"submit\"name=\"送信\" value=\"検索する\"/>\n";
    print "<INPUT type=\"button\"name=\"clear\" value=\"クリア\" onclick=\"document.all.INPUT.value=''\"/>\n";

    print "<TABLE style=\"border=0px solid silver;padding: 0.25em;margin: 0.25em;\"><TR><TD>検索条件</TD>\n";
    if($params{'logical_operator'} eq "OR"){
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"DPND_AND\"/>全ての係り受けを含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"WORD_AND\"/>全ての語を含む</LABEL></TD>\n";
	print "<TD><LABEL><INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>いずれかの語を含む</LABEL></TD>\n";
    }elsif($params{'logical_operator'} eq "AND"){
	if($params{'force_dpnd'} > 0){
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

    if ($params{syngraph}) {
	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT>同義表現を考慮する</LABEL></TD></TR>\n";
    } else {
	print "<TR><TD>オプション</TD><TD colspan=3 DIV style=\"text-align:left;\"><INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL>同義表現を考慮する</LABEL></DIV></TD></TR>\n";
    }
    print "</TABLE>\n";
    
    print "</FORM>\n";

#    print ("<FONT color='red'>サーバーメンテナンスのため、TSUBAKI APIをご利用いただけません。</FONT>\n");
    
    print "</CENTER>";
}
