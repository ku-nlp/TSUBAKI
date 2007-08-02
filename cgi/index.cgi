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

# 定数
my $INDEX_DIR = '/work/skeiji/dat';
my @HIGHLIGHT_COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", "880000", "00aa00", "886800", "004699", "990099");
my $TOOL_HOME = '/home/skeiji/local/bin';
my $ORDINARY_DFDB_PATH = '/var/www/cgi-bin/dbs/dfdbs';
my $SYNGRAPH_DFDB_PATH = '/data/idx_syn/dfdbs';
my $LOG_FILE_PATH = '/se_tmp/input.log';

my $KNP_PATH = $TOOL_HOME;
my $JUMAN_PATH = $TOOL_HOME;
my $SYNDB_PATH = '/home/skeiji/SynGraph/syndb/i686';

my $SYNGRAPH_SF_PATH = '/net2/nlpcf34/disk07/skeiji';
my $ORDINARY_SF_PATH = '/net/nlpcf2/export2/skeiji/data/xmls';
my $MAX_NUM_OF_WORDS_IN_SNIPPET = 100;
my $MAX_LENGTH_OF_TITLE = 30;
my $TITLE_DB_FP = '/var/www/cgi-bin/dbs/title.cdb';
my $HTML_FILE_PATH = '/net2/nlpcf34/disk02/skeiji/htmls';
my $URL_DB_PATH = '/var/www/cgi-bin/dbs';

&main();

sub main {
    # cgiパラメタの取得
    my $params = &get_cgi_parameters();

    # HTTPヘッダ出力
    print header(-charset => 'utf-8');

    if ($params->{'URL'}) {
	# キャッシュページの出力
	&print_cached_page($params);
    } else {
	# TSUBAKI のトップ画面を表示
	&print_tsubaki_interface($params);

	unless ($params->{query}) {
	    # フッターの表示
	    &print_footer($params, 0, 0);
	} else {
	    # クエリが入力された場合は検索
	    # 検索クエリの構造体を取得
	    my $query = &parse_query($params);

	    # 検索エンジンオブジェクトの初期化
	    my $se_obj = new SearchEngine($params->{syngraph});
	    ($params->{syngraph} > 0) ? $se_obj->init($SYNGRAPH_DFDB_PATH) : $se_obj->init($ORDINARY_DFDB_PATH);

	    # 検索
	    my $start_time = Time::HiRes::time;
	    my ($hitcount, $results) = $se_obj->search($query);
	    my $search_time = Time::HiRes::time - $start_time; # 検索に要した時間を取得

	    # ログの出力
	    &save_log($params, $hitcount, $search_time);

	    # 検索クエリの表示
	    my $cbuff = &print_query($query->{keywords});
	    if ($hitcount < 1) {
		print ") を含む文書は見つかりませんでした。</DIV>";
	    } else {
		# ヒット件数の表示
		print ") を含む文書が ${hitcount} 件見つかりました。"; 

		my $size = $params->{'start'} + $params->{'results'};
		$size = $hitcount if ($hitcount < $size);
		$params->{'results'} = $hitcount if ($params->{'results'} > $hitcount);

		if ($hitcount > $params->{'results'}) {
		    print "スコアの上位" . ($params->{'start'} + 1) . "件目から" . $size . "件目までを表示しています。<BR></DIV>";
		} else {
		    print "</DIV>";
		}
		# 検索にかかった時間を表示 (★cssに変更)
		printf("<div style=\"text-align:right;background-color:white;border-bottom: 0px solid gray;mergin-bottom:2em;\">%s: %3.3f [%s]</div>\n", encode('utf8', '検索時間'), $search_time, encode('utf8', '秒'));
		
		# 検索サーバから得られた検索結果のマージ
		my $mg_result = &merge_search_results($results, $size);

		# 検索結果の表示
		&print_search_result($params, $mg_result, $query, $params->{'start'}, $size, $hitcount, $cbuff);
	    }
	    # フッターの表示
	    &print_footer($params, $hitcount, $params->{'start'});
	}
    }
}

# ログの保存
sub save_log {
    my ($params, $hitcount, $search_time) = @_;
    my $date = `date +%m%d-%H%M%S`; chomp ($date);
    open(OUT, ">> $LOG_FILE_PATH");
    my $param_str;
    foreach my $k (sort keys %{$params}) {
	$param_str .= "$k=$params->{$k},";
    }
    $param_str .= "hitcount=$hitcount,time=$search_time";
    print OUT "$date $ENV{REMOTE_ADDR} SEARCH $param_str\n";
    close(OUT);
}

# 検索サーバから得られた検索結果をマージする
sub merge_search_results {
    my ($results, $size) = @_;

    my $max = 0;
    my @merged_result;
    while (scalar(@merged_result) < $size) {
	for (my $i = 0; $i < scalar(@{$results}); $i++) {
	    next unless (defined($results->[$i][0]));

	    $max = $i if ($results->[$max][0]{score} <= $results->[$i][0]{score});
	}
	
	push(@merged_result, shift(@{$results->[$max]}));
    }
    return \@merged_result;
}

# 検索クエリを解析する
sub parse_query {
    my ($params) = @_;
    my $q_parser = new QueryParser({
	KNP_PATH => $KNP_PATH,
	JUMAN_PATH => $JUMAN_PATH,
	SYNDB_PATH => $SYNDB_PATH,
	KNP_OPTIONS => ['-postprocess','-tab'] });
    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;
    
    # クエリの解析
    # logical_cond_qk: クエリ間の論理演算
    my $query = $q_parser->parse($params->{query}, {logical_cond_qk => $params->{logical_operator}, syngraph => $params->{syngraph}});
    # 取得ページ数のセット
    $query->{results} = $params->{results};
    
    # 検索語にインターフェースより得られる検索制約を追加
    foreach my $qk (@{$query->{keywords}}) {
	$qk->{force_dpnd} = 1 if ($params->{force_dpnd});
	$qk->{logical_cond_qkw} = 'OR' if ($params->{logical_operator} eq 'OR');
    }

    return $query;
}

# キャッシュされたページを表示
sub print_cached_page {
    my ($params) = @_;

    my $color;
    my $html = '';
    if (-e $params->{'URL'}) {
	$html = `$TOOL_HOME/nkf -w $params->{'URL'}`;
    } else {
	my $newurl = $params->{'URL'} . ".gz";
	$html = `gunzip -c  $newurl | $TOOL_HOME/nkf -w`;
    }
    $html = decode('utf8', $html);
    $html =~ s/charset=//i;

    # KEYごとに色を付ける
    my @KEYS = split(/:/, decode('utf8', $params->{'KEYS'}));
    print "<DIV style=\"padding:1em; background-color:#f1f4ff; border-top:1px solid gray; border-bottom:1px solid gray;\"><U>次のキーワードがハイライトされています:&nbsp;";
    for my $key (@KEYS) {
	next unless ($key);

	print "<span style=\"background-color:#$HIGHLIGHT_COLOR[$color];\">";
	print encode('utf8', $key) . "</span>&nbsp;";
	if($color > 4){
	    # background-color が暗いので foreground-color を白に変更
	    $html =~ s/$key/<span style="color:white; background-color:#$HIGHLIGHT_COLOR[$color];">$key<\/span>/g;
	}else{
	    $html =~ s/$key/<span style="background-color:#$HIGHLIGHT_COLOR[$color];">$key<\/span>/g;
	}
	$color = (++$color%scalar(@HIGHLIGHT_COLOR));
    }
    print "</U></DIV>";
    print encode('utf8', $html);
}

# cgiパラメタを取得
sub get_cgi_parameters {
    my %params = ();
    my $cgi = new CGI;

    $params{'start'} = 0;
    $params{'logical_operator'} = 'WORD_AND';
    $params{'dpnd'} = 1;
    $params{'results'} = 50;
    $params{'force_dpnd'} = 0;
    $params{'filter_simpages'} = 0;
    $params{'near'} = 0;
    $params{'syngraph'} = 0;


    # 指定された検索条件に変更
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

    $params{'KEYS'} = $cgi->param('KEYS');

    return \%params;
}

# 装飾されたスニペットを生成する関数
sub create_decorated_snippet {
    my ($did, $query, $params, $color) = @_;

    # snippet用に重要文を抽出
    my $sentences;
    if ($params->{'syngraph'}) {
	my $xmlpath = sprintf("%s/%02d/x%04d/%08d.xml", $SYNGRAPH_SF_PATH, $did / 1000000, $did / 10000, $did);
	$sentences = &SnippetMaker::extractSentencefromSynGraphResult($query->{keywords}, $xmlpath);
    } else {
	my $filepath = sprintf("%s/x%04d/%08d.xml", $ORDINARY_SF_PATH, $did / 10000, $did);
	unless (-e $filepath || -e "$filepath.gz") {
	    $filepath = sprintf("/net2/nlpcf34/disk02/skeiji/xmls/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
	}
	$sentences = &SnippetMaker::extractSentencefromKnpResult($query->{keywords}, $filepath);
    }

    my $snippet;
    my $wordcnt = 0;
    # スコアの高い順に処理
    foreach my $sentence (sort {$b->{score} <=> $a->{score}} @{$sentences}) {
	for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
	    my $highlighted = -1;
	    my $surf = $sentence->{surfs}[$i];
	    foreach my $rep (@{$sentence->{reps}[$i]}) {
		if (exists($color->{$rep})) {
		    # 代表表記レベルでマッチしたらハイライト
		    $snippet .= sprintf("<span style=\"color:%s;margin:0.1em 0.25em;background-color:%s;\">%s<\/span>", $color->{$rep}->{foreground}, $color->{$rep}->{background}, $surf);
		    $highlighted = 1;
		}
		last if ($highlighted > 0);
	    }
	    # ハイライトされなかった場合
	    $snippet .= $surf if ($highlighted < 0);
	    $wordcnt++;

	    # スニペットが N 単語を超えた終了
	    if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET) {
		$snippet .= " <b>...</b>";
		last;
	    }
	}
	# ★ 多重 foreach の脱出に label をつかう
	last if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET);
    }

    # フレーズの強調表示
    foreach my $qk (@{$query->{keywords}}){
	next unless ($qk->{near} == 0);
	$snippet =~ s!$qk->{rawstring}!<b>$qk->{rawstring}</b>!g;
    }

    $snippet = encode('utf8', $snippet) if (utf8::is_utf8($snippet));

    return $snippet;
}

sub print_search_result {
    my ($params, $result, $query, $from, $end, $hitcount, $color) = @_;

    # キャッシュページで索引語をハイライトさせるため、索引語をuri_escapeした文字列を生成する
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
    my $uri_escaped_search_keys = &uri_escape(encode('utf8', $search_k));

    my %urldbs = ();
    tie my %titledb, 'CDB_File', $TITLE_DB_FP or die "$0: can't tie to $TITLE_DB_FP $!\n";

    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%08d", $result->[$rank]{did});
	my $score = $result->[$rank]{score};
	my $htmlpath = sprintf("%s/%02d/h%04d/%08d.html", $HTML_FILE_PATH, $did / 1000000, $did / 10000, $did);
	
	# 装飾されたスニペッツの生成
	my $snippet = &create_decorated_snippet($did, $query, $params, $color);

	# タイトルの取得
	my $htmltitle = 'no title';
	$htmltitle = decode('euc-jp', $titledb{$did}) if (exists($titledb{$did}));
	$htmltitle =~ s/(.{$MAX_LENGTH_OF_TITLE}).*/\1 <B>\.\.\.<\/B>/ if (length($htmltitle) > $MAX_LENGTH_OF_TITLE); # 長い場合は省略

	# URL の取得
	my $did_prefix = sprintf("%02d", $did / 1000000);
	my $url = $urldbs{$did_prefix}->{$did};
	unless (defined($url)) {
	    my $urldbfp = "$URL_DB_PATH/$did_prefix.url.cdb";
	    tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
	    $urldbs{$did_prefix} = \%urldb;
	    $url = $urldb{$did};
	}

	my $output = "<DIV class=\"result\">";
	$score = sprintf("%.4f", $score);
	$output .= "<SPAN class=\"rank\">" . ($rank + 1) . "</SPAN>";
	$output .= "<A class=\"title\" href=index.cgi?URL=$htmlpath&KEYS=" . $uri_escaped_search_keys . " target=\"_blank\" class=\"ex\">";
	$output .= encode('utf8', $htmltitle) . "</a>";
	$output .= "<DIV class=\"meta\">id=$did, score=$score</DIV>\n";
	$output .= "<BLOCKQUOTE class=\"snippet\">$snippet</BLOCKQUOTE>";
	$output .= "<A class=\"cache\" href=\"$url\">$url</A>\n";
	$output .= "</DIV>";

	# 1 ページ分の結果を表示
	print $output;
    }

    # DB の untie
    foreach my $k (keys %urldbs){
	untie %{$urldbs{$k}};
    }
    untie %titledb;
}

sub print_footer {
    my ($params, $hitcount, $from) = @_;
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

    <DIV class="footer">&copy;2007 黒橋研究室</DIV>
    </body>
    </html>
END_OF_HTML
}

sub print_query {
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
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'white';
			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'black';
			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
			}
			$color = (++$color%scalar(@HIGHLIGHT_COLOR));
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
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'white';
			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$HIGHLIGHT_COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$rep->{string}}->{foreground} = 'black';
			    $cbuff{$rep->{string}}->{background} = "#$HIGHLIGHT_COLOR[$color]";
			}
			$color = (++$color%scalar(@HIGHLIGHT_COLOR));
		    }
		}
	    }
	}
    }

    return \%cbuff;
}

sub print_tsubaki_interface {
    my ($params) = @_;
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
	print "<TR><TD>オプション</TD><TD colspan=3 style=\"text-align:left;\"><LABEL><INPUT type=\"checkbox\" name=\"syngraph\" checked></INPUT>同義表現を考慮する</LABEL></TD></TR>\n";
    } else {
	print "<TR><TD>オプション</TD><TD colspan=3 DIV style=\"text-align:left;\"><INPUT type=\"checkbox\" name=\"syngraph\"></INPUT><LABEL>同義表現を考慮する</LABEL></DIV></TD></TR>\n";
    }
    print "</TABLE>\n";
    
    print "</FORM>\n";

#    print ("<FONT color='red'>サーバーメンテナンスのため、TSUBAKI APIをご利用いただけません。</FONT>\n");
    
    print "</CENTER>";
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
