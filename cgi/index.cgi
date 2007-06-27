#!/home/skeiji/local/bin/perl
#!/usr/bin/env perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use Encode;
use utf8;

use IO::Socket;
use IO::Select;
use Time::HiRes;
use CDB_File;

use SearchEngine;
use QueryParser;
use SnippetMaker;

## 定数
my $INDEX_DIR = '/var/www/cgi-bin/tsubaki/INDEX_NTCIR2';
my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", "880000", "00aa00", "886800", "004699", "990099");
my $PORT = 99557;
my $TOOL_HOME='/home/skeiji/local/bin';
my @HOSTS;
for(my $i = 161; $i < 192; $i++){
    next if ($i == 188);
    next if ($i == 187);
    next if ($i == 186);
    push(@HOSTS,   "157.1.128.$i");
#    last;
}

my $cgi = new CGI;
my %params = ();
## 検索条件の初期化
$params{'ranking_method'} = 'OKAPI';
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
$params{'only_hitcount'} = 0;


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

#    $params{'query'} = undef;
    
    # 入力があった場合
    if($params{'query'}){
	# parse query
	my $start_time_genuine = Time::HiRes::time;

	my $query_objs;
	if ($params{'syngraph'}) {
	    $query_objs = &QueryParser::parse_with_syngraph($params{'query'}, \%params);
	    $PORT= 95666;
	    if ($query_objs->{contains_phrasal_query}) {
		print "<center>同義表現を考慮したフレーズ検索は実行できません。</center></DIV>\n";
		print "<DIV class=\"footer\">&copy;2007 黒橋研究室</DIV>\n";
		print "</body>\n";
		print "</html>\n";
		exit;
	    } elsif ($query_objs->{contains_near_operator}) {
		print "<center>同義表現を考慮した近接検索は実行できません。</center></DIV>\n";
		print "<DIV class=\"footer\">&copy;2007 黒橋研究室</DIV>\n";
		print "</body>\n";
		print "</html>\n";
		exit;
	    }
	} else {
	    $query_objs = &QueryParser::parse($params{'query'}, \%params);
	}

	## 検索
	my $se_obj = new SearchEngine(\@HOSTS, $PORT, 'SEARCH_ENGINE');
	my $start_time = Time::HiRes::time;
	my ($hitcount, $results) = $se_obj->search($query_objs->{query}, \%params);
	my $finish_time = Time::HiRes::time;
	my $search_time = $finish_time - $start_time;

	# 検索クエリの表示
	my $cbuff = &printQueries($query_objs->{query});

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
 	    while($until > scalar(@merged_results)){
 		for(my $k = 0; $k < scalar(@{$results}); $k++){
 		    next unless(defined($results->[$k]->[0]));
	
 		    if($results->[$max]->[0]->{score} <= $results->[$k]->[0]->{score}){
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
#$params{'query'} $params{'ranking_method'} $params{'logical_operator'} $hitcount $search_time\n";
		$param_str .= "$k=$params{$k},";
	    }
	    $param_str .= "hitcount=$hitcount,time=$search_time";
 	    print OUT "$date $ENV{REMOTE_ADDR} SEARCH $param_str\n";
 	    close(OUT);

	    my $search_k;
	    foreach my $q (@{$query_objs->{query}}){
		my $words = $q->{words};
 		foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}){
		    foreach my $rep (@{$reps}){
			$search_k .= "$rep->{rawstring}:";
		    }
		}
		
 		my $dpnds = $q->{dpnds};
 		foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$dpnds}){
 		    foreach my $rep (@{$reps}){
 			$search_k .= "$rep->{rawstring}:";
 		    }
 		}
	    }
	    chop($search_k);
	    
	    $params{'query'} =~ s/\s/:/g;
	    $params{'query'} =~ s/　/:/g;
	    my %urldbs = ();
	    my $dbfp = "title.cdb";
	    tie my %titledb, 'CDB_File', $dbfp or die "$0: can't tie to $dbfp $!\n";
	    my $prev_page = {title => undef, url => undef, snippets => undef, score => 0};
	    for(my $rank = $params{'start'}; $rank < scalar(@merged_results); $rank++){
		my $did = $merged_results[$rank]->{did};
		my $score =  $merged_results[$rank]->{score};
		my $url = sprintf("$INDEX_DIR/%02d/h%04d/%08d.html", $did / 1000000, $did / 10000, $did);
		my $htmlpath = $url;

		## snippet用に重要文を抽出
		my $sent_objs;
		if ($params{'syngraph'}) {
		    my $xmlpath = sprintf("/net2/nlpcf34/disk07/skeiji/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
		    $sent_objs = &SnippetMaker::extractSentencefromSynGraphResult($query_objs, $xmlpath);
		} else {
		    my $xmlpath = sprintf("$INDEX_DIR/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
		    $sent_objs = &SnippetMaker::extractSentencefromKnpResult($query_objs, $xmlpath);
		}

 		my $snippet = '';
		my %words = ();
 		my $length = 0;
 		foreach my $sent_obj (sort {$b->{score} <=> $a->{score}} @{$sent_objs}){
		    my $fflag = -1;
		    foreach my $q_obj (@{$query_objs->{query}}){
			if(index($sent_obj->{rawstring}, $q_obj->{rawstring}) > 0){
			    $fflag = 1;
			    last;
			}
		    }
#		    next if($fflag < 0);

 		    my @mrph_objs = @{$sent_obj->{list}};
 		    foreach my $m (@mrph_objs){
 			my $surf = $m->{surf};
 			my $reps = $m->{reps};

			foreach my $k (keys %{$reps}){
			    $words{$k} += $reps->{$k};
			}

 			my $color = 0;
 			my $flag = -1;
 			foreach my $k (%{$cbuff}){
 			    if(exists($reps->{$k})){
				$snippet .= sprintf("<span style=\"color:%s;margin:0.1em 0.25em;background-color:%s;\">$surf<\/span>", $cbuff->{$k}->{foreground}, $cbuff->{$k}->{background});
 				$flag = 1;
 				last;
 			    }
 			}
 			$snippet .= $surf if($flag < 0);

 			$length += length($surf);
 			if($length > 200){
 			    $snippet .= " <b>...</b>";
			    last;
 			}
 		    }
 		    last if($length > 200);
 		}

		## フレーズの強調表示
		foreach my $q (@{$query_objs->{query}}){
		    next unless ($q->{near} == 1); 
		    $snippet =~ s!$q->{rawstring}!<b>$q->{rawstring}</b>!g;
		}

 		$snippet = encode('utf8', $snippet) if(utf8::is_utf8($snippet));
  		$did = sprintf("%08d", $did);
 		my $htmltitle = 'no title';
 		$htmltitle = decode('euc-jp', $titledb{$did}) if(exists($titledb{$did}));
 		if(length($htmltitle) > 30){
 		    $htmltitle =~ s/(.{30}).*/\1 <B>\.\.\.<\/B>/;
 		}

 		my $url;
 		$did =~ /(\d\d)\d\d\d\d\d\d$/;
 		if(exists($urldbs{$1})){
 		    $url = $urldbs{$1}->{$did};
 		}else{
 		    my $urldbfp = "/var/www/cgi-bin/dbs/$1.url.cdb";
 		    tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
 		    $urldbs{$1} = \%urldb;
 		    $url = $urldb{$did};
 		}

  		my $output = "<DIV class=\"result\">";
		if($prev_page->{title} eq $htmltitle &&
		   $prev_page->{score} == $score){
		    if($params{'filter_simpages'}){
			next;
		    }
		    $output = "<DIV class=\"similar\">";
		}else{
		    my $sim = 0;
		    if(defined($prev_page->{words})){
			$sim = &calculateSimilarity($prev_page->{words}, \%words);
		    }
		    if($sim > 0.9){
			$output = "<DIV class=\"similar\">";
		    }

		    $prev_page->{words} = \%words;
		    $prev_page->{title} = $htmltitle;
		    $prev_page->{score} = $score;

		    if($params{'filter_simpages'} && $sim > 0.9){
			next;
		    }
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
		my $finish_time = Time::HiRes::time;
		my $hyouji_time = $finish_time - $start_time_genuine;
#		print "<font color=white>$hyouji_time</font><br>\n"
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
#   return $sim;
}

sub extractSentence {
    my($query, $xmlpath) = @_;

    my @sent_objs = ();
    if(-e $xmlpath){
	open(READER, $xmlpath);
    }else{
	$xmlpath .= ".gz";
	open(READER,"zcat $xmlpath |");
    }

    my $buff;
    while(<READER>){
	$buff .= $_;
	if($_ =~ m!</Annotation>!){
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"Knp\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
		my %temp1 = ();
		my @temp2 = ();
		my $knpresult = $1;
		my $sent_obj = {rawstring => undef,
				words => \%temp1,
				list => \@temp2,
				score => 0.0
		};
		
		foreach my $line (split(/\n/, $knpresult)){
		    next if($line =~ /^\* /);
		    next if($line =~ /^\+ /);
		    next if($line =~ /EOS/);
		    
		    my @m = split(/\s+/, $line);
		    my $surf = $m[0];
		    my $word = $m[2];
		    my $mrph_obj = {surf => undef,
				    reps => undef
		    };

		    $sent_obj->{rawstring} .= $surf;
		    $mrph_obj->{surf} = $surf;
		    if($line =~ /\<意味有\>/){
			next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
			
			my %reps = ();
			## 代表表記の取得
			if($line =~ /代表表記:(.+?)\//){
			    $word = $1;
			}

			$reps{$word} = 1;
			## 代表表記に曖昧性がある場合は全部保持する
			while($line =~ /\<ALT(.+?)\>/){
			    $line = "$'";
			    if($1 =~ /代表表記:(.+?)\//){
				$reps{$word} = 1;
			    }
			}

			my $size = scalar(keys %reps);
			foreach my $w (keys %reps){
			    $w = &h2z_ascii($w);
			    $sent_obj->{words}->{$w} = 0 unless(exists($sent_obj->{words}->{$w}));
			    $sent_obj->{words}->{$w} += (1 / $size);
			}
			$mrph_obj->{reps} = \%reps;
		    }
		    push(@{$sent_obj->{list}}, $mrph_obj);
		}
			    
		my $score = 0;
		foreach my $k (keys %{$query->{words}}){
		    $score += $sent_obj->{words}->{$k} if(exists($sent_obj->{words}->{$k}));
		}

		foreach my $k (keys %{$query->{ngrams}}){
		    $score += 1 if($sent_obj->{rawstring} =~ /$k/);
		}

		if($score > 0){
#		    $sent_obj->{score} = ($score * length($sent_obj->{rawstring}));
		    $sent_obj->{score} = ($score * log(length($sent_obj->{rawstring})));
		    push(@sent_objs, $sent_obj);
		}
	    }
	    $buff = '';
	}
    }
    close(READER);

    return \@sent_objs;
}

sub h2z_ascii {
    my($string) = @_;

    $string =~ s/ａ/Ａ/g;
    $string =~ s/ｂ/Ｂ/g;
    $string =~ s/ｃ/Ｃ/g;
    $string =~ s/ｄ/Ｄ/g;
    $string =~ s/ｅ/Ｅ/g;
    $string =~ s/ｆ/Ｆ/g;
    $string =~ s/ｇ/Ｇ/g;
    $string =~ s/ｈ/Ｈ/g;
    $string =~ s/ｉ/Ｉ/g;
    $string =~ s/ｊ/Ｊ/g;
    $string =~ s/ｋ/Ｋ/g;
    $string =~ s/ｌ/Ｌ/g;
    $string =~ s/ｍ/Ｍ/g;
    $string =~ s/ｎ/Ｎ/g;
    $string =~ s/ｏ/Ｏ/g;
    $string =~ s/ｐ/Ｐ/g;
    $string =~ s/ｑ/Ｑ/g;
    $string =~ s/ｒ/Ｒ/g;
    $string =~ s/ｓ/Ｓ/g;
    $string =~ s/ｔ/Ｔ/g;
    $string =~ s/ｕ/Ｕ/g;
    $string =~ s/ｖ/Ｖ/g;
    $string =~ s/ｗ/Ｗ/g;
    $string =~ s/ｘ/Ｘ/g;
    $string =~ s/Y/Ｙ/g;
    $string =~ s/Z/Ｚ/g;

    return $string;
}

sub printQueries {
    my($query_objs) = @_;

    my %cbuff = ();
    my $color = 0;
    print "<DIV style=\"padding: 0.25em 1em; background-color:#f1f4ff;border-top: 1px solid gray;border-bottom: 1px solid gray;mergin-left:0px;\">検索キーワード (";
    foreach my $q (@{$query_objs}){
	if ($q->{near} == 1) {
	    printf("<b style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$q->{rawstring}</b>");
	} else {
	    my $words = $q->{words};
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}){
		foreach my $k (@{$reps}){
		    next if($k->{isContentWord} < 1 && $q->{near} < 1);

		    my $k_utf8 = encode('utf8', $k->{rawstring});
		    if(exists($cbuff{$k})){
			printf("<span style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$k->{rawstring}}->{foreground}, $cbuff{$k->{rawstring}}->{background});
		    }else{
			if($color > 4){
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$k->{rawstring}}->{foreground} = 'white';
			    $cbuff{$k->{rawstring}}->{background} = "#$COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$k->{rawstring}}->{foreground} = 'black';
			    $cbuff{$k->{rawstring}}->{background} = "#$COLOR[$color]";
			}
			$color = (++$color%scalar(@COLOR));
		    }
		}
	    }
	    
	    my $dpnds = $q->{dpnds};
	    foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$dpnds}){
		foreach my $k (@{$reps}){
		    my $k_tmp  = $k->{rawstring};
		    $k_tmp =~ s/->/→/;
		    my $k_utf8 = encode('utf8', $k_tmp);
		    if(exists($cbuff{$k->{rawstring}})){
			printf("<span style=\"margin:0.1em 0.25em;color=%s;background-color:%s;\">$k_utf8</span>", $cbuff{$k->{rawstring}}->{foreground}, $cbuff{$k->{rawstring}}->{background});
		    }else{
			if($color > 4){
			    print "<span style=\"color:white;margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$k->{rawstring}}->{foreground} = 'white';
			    $cbuff{$k->{rawstring}}->{background} = "#$COLOR[$color]";
			}else{
			    print "<span style=\"margin:0.1em 0.25em;background-color:#$COLOR[$color];\">$k_utf8</span>";
			    $cbuff{$k->{rawstring}}->{foreground} = 'black';
			    $cbuff{$k->{rawstring}}->{background} = "#$COLOR[$color]";
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
    print "<INPUT type=\"text\" name=\"INPUT\" value=\'$params{'query'}\'/ size=\"50\">\n";
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
    
    print "<DIV>\n";
#    if($params{'dpnd'} == 1){
#	print "<INPUT type=\"checkbox\" name=\"dpnd\" value=\"1\" checked/>係り受けを考慮する\n";
#    }else{
#	print "<INPUT type=\"checkbox\" name=\"dpnd\" value=\"1\"/>係り受けを考慮する\n";
#    }

#    if($params{'filter_simpages'} == 1){
#	print "<INPUT type=\"checkbox\" name=\"filter_simpages\" value=\"1\" checked/>類似ページを表示しない\n";
#    }else{
#	print "<INPUT type=\"checkbox\" name=\"filter_simpages\" value=\"1\"/>類似ページを表示しない\n";
#    }

    print "</DIV>\n";
    print "</FORM>\n";

#    print ("<FONT color='red'>サーバーメンテナンスのため、検索・APIともにサービスを一時的に停止致しております。</FONT>\n");
    
    print "</CENTER>";
}
