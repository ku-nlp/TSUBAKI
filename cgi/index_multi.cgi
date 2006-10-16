#!/home/skeiji/local/bin/perl
#!/usr/bin/env perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use Retrieve;
use Encode;

use IO::Socket;
use IO::Select;
use Time::HiRes;

my $cgi = new CGI;
my $URL = $cgi->param('URL');
my $INPUT = $cgi->param('INPUT');
my $RANKING_METHOD = $cgi->param('rank');
my $LOGICAL_COND = $cgi->param('logical');

my $date = `date +%m%d-%H%M%S`;
chomp ($date);

my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", 
	     "880000", "00aa00", "886800", "004699", "990099");


# my $retrieve_script_dir = '/usr/local/apache/htdocs/SearchEngine/scripts/';
# my $INDEX_dir = '/share3/text/WWW/tau060911';
my $PRINT_THRESHOLD = 50;

# unless(@ARGV){
#     for(my $i = 1; $i < 24; $i++){
# 	if($i > 9){
# 	    push(@ARGV, "nlpc$i");
# 	}else{
# 	    push(@ARGV, "nlpc0$i");
# 	}
#     }
# }

my @hosts;
for(my $i = 1; $i < 24; $i++){
    if($i > 9){
	push(@hosts, "nlpc$i");
    }else{
	push(@hosts, "nlpc0$i");
    }
}
# $hosts[0] = "nlpc22";
# $hosts[1] = "nlpc23";
# $hosts[2] = "nlpc01";

#my @hosts = @ARGV;
my $port = 9686;

#my $retrieve = new Retrieve($INDEX_dir);
my $tool_home='/home/skeiji/local/bin';

# HTTPヘッダ出力
print header(-charset => 'euc-jp');

# 指定されたＵＲＬの表示       
if ($URL) {

    my $color;
    my $html = `$tool_home/nkf -e $URL`;
    
    # 元ファイルのヘッダを削除するため、最初の空行より上を削除
    $html =~ s/^.*?\n\s*\n//s;

    # KEYごとに色を付ける
    my @KEYS = split(/:/, $cgi->param('KEYS'));   	
    print "<BR><U>以下のキーワードがハイライトされています:";
    for my $key (@KEYS) {
	next unless ($key);
	print "<span style=\"background-color:#$COLOR[$color];\">$key</span>";
	$html =~ s/$key/<span style="background-color:#$COLOR[$color];">$key<\/span>/g;
	$color++;
    }
    print "</U><BR><BR>$html";
}

else {

    # HTMl出力
    print << "END_OF_HTML";
    <html>
	<head>
	<title>Search Engine</title>
	<link rel="stylesheet" type="text/css" href="cf.css">
	</head>
	<body>
END_OF_HTML

    # タイトル出力
    print h1('検索エンジン');
    
    # フォーム出力
    print "<FORM method=\"post\" action=\"\" enctype=\"multipart/form-data\">\n";
    print "入力: <INPUT type=\"text\" name=\"INPUT\" value=\"$INPUT\"/>\n";
    print "<INPUT type=\"submit\"name=\"送信\" value=\"送信\"/>\n";

#   print "<INPUT type=\"radio\" name=\"rank\" value=\"AND\"/>\n";
    if($RANKING_METHOD eq "OKAPI"){
	print "<INPUT type=\"radio\" name=\"rank\" value=\"TFIDF\"/>TFIDF\n";
	print "<INPUT type=\"radio\" name=\"rank\" value=\"OKAPI\" checked/>OKAPI\n";
    }else{
	print "<INPUT type=\"radio\" name=\"rank\" value=\"TFIDF\" checked/>TFIDF\n";
	print "<INPUT type=\"radio\" name=\"rank\" value=\"OKAPI\"/>OKAPI\n";
    }

    if($LOGICAL_COND eq "AND"){
	print "<INPUT type=\"radio\" name=\"logical\" value=\"AND\" checked/>AND\n";
	print "<INPUT type=\"radio\" name=\"logical\" value=\"OR\"/>OR\n";
    }else{
	print "<INPUT type=\"radio\" name=\"logical\" value=\"AND\"/>AND\n";
	print "<INPUT type=\"radio\" name=\"logical\" value=\"OR\" checked/>OR\n";
    }

    print "</FORM>\n";
    print "<HR>\n";
    
    # 入力があった場合
    if ($INPUT) {
	
	# ログの保存
	open(OUT, ">> /se_tmp/input.log");
	print OUT "$date $ENV{REMOTE_ADDR}\t$INPUT $RANKING_METHOD $LOGICAL_COND\n";
	close OUT;
	
	my $hitcount = 0;
	my $selecter = IO::Select->new;

	my $start_time = Time::HiRes::time;
	# 解析
	for(my $i = 0; $i < scalar(@hosts); $i++){
	    my $host = $hosts[$i];
#	    print "$host:$port に接続します。\n";
	    
	    my $socket = IO::Socket::INET->new(PeerAddr => $host,
					       PeerPort => $port,
					       Proto    => 'tcp',
					       );
	    $selecter->add($socket);
	    unless($socket){
		die "$host に接続できませんでした。 $!\n";
	    }
	    
	    # 文字列を送信
#	    print "送信メッセージ: $query\n";
	    print $socket "$INPUT,$RANKING_METHOD,$LOGICAL_COND\n";
	    $socket->flush();
	}
	
	# 文字列を受信
	my @results;
	my $num_of_sockets = scalar(@hosts);
	while($num_of_sockets > 0){
	    my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	    foreach my $socket (@{$readable_sockets}){
		my $buff = <$socket>;
		chop($buff);
		$hitcount += $buff;
		
		$buff = <$socket>;
		$buff =~ s/\[RET\]/\n/g;
		push(@results, &decodeResult($buff));
		
		$selecter->remove($socket);
		$socket->close();
		$num_of_sockets--;
	    }
	}
	
	# 解析結果の表示
	my $color;
	for my $key (split(/\s/, $INPUT)) {
	    next unless ($key);
	    print " <span style=\"background-color:#$COLOR[$color];\">$key</span>";
	    $color++;
	}
	print ": ";

	if($hitcount < 1){
	    print "No file was found";
	}else{
	    my $output;
 	    print "$hitcount個のファイルが見つかりました<BR>";
 	    print "最初の${PRINT_THRESHOLD}件を表示します<BR>" if $hitcount > $PRINT_THRESHOLD;

	    my $max = 0;
	    my @merged_results;
	    while($PRINT_THRESHOLD > scalar(@merged_results)){
		for(my $k = 0; $k < scalar(@results); $k++){
		    next unless(defined($results[$k]->[0]));
		
		    if($results[$max]->[0]->{score} <= $results[$k]->[0]->{score}){
			$max = $k;
		    }
		}
		push(@merged_results, shift(@{$results[$max]}));
	    }


	    my $finish_time = Time::HiRes::time;
	    printf("<div style=\"text-align:right;background-color:#efefef;\">time: %3.3f [seconds]</div>\n", ($finish_time-$start_time));

	    $INPUT =~ s/\s/:/g;
	    $INPUT =~ s/　/:/g;
	    for(my $rank = 0; $rank < scalar(@merged_results); $rank++){
		my $did = $merged_results[$rank]->{did};
		my $score =  $merged_results[$rank]->{score};
 		my $url = sprintf("INDEX/%02d/h%04d/%08d.html", $did / 1000000, $did / 10000, $did);
 		my $xmlpath = sprintf("INDEX/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);

		my $htmldoc = `$tool_home/nkf -e $url`;
		my $htmltitle = 'no title';
		$htmldoc =~ /\<title\>((?:.|\n)+)\<\/title\>/i;
		$htmltitle = $1 if($1 ne '');

		my $xmldoc = `$tool_home/nkf -e $xmlpath`;
		my $snippet = '';
		foreach my $q (split(/:/, $INPUT)){
		    my $buff = $xmldoc;
		    my $longest = '';
		    while($buff =~ /\<RawString\>(.*$q.*)\<\/RawString\>/){
			$longest = $1 if(length($longest) < length($1) && length($1) < 200);
			last if(length($longest) > length($q) + 40);
			$buff = "$'";
		    }
		    $snippet .= "$longest... ";
		}
		chop($snippet);
		chop($snippet);
		chop($snippet);
		chop($snippet);

		my $orgurl = `head -1 ${url} | cut -f 2 -d ' '`;

 		$did = sprintf("%08d", $did);
 		$score = sprintf("%.4f", $score);

 		my $output = "<a href=index.cgi?URL=$url&KEYS=";
		$output .= &uri_escape($INPUT) . " target=\"_blank\" class=\"ex\">$htmltitle</a>";
		$output .= "<sub style=\"font-size:small;color:silver;\">(id=$did, score=$score)</sub>\n";
		$output .= "<BLOCKQUOTE>$snippet<ADDRESS>http://$orgurl</ADDRESS></BLOCKQUOTE>\n";
		print $output;
	    }

#		for(my $h = 0; $h < scalar(@{$results[$k]}); $h++){
#		    print "$h: did=" . $results[$k]->[$h]->{did} . "@" . $results[$k]->[$h]->{score} . "<BR>\n";
#		}
#	    }

# 	    my $count = 0;
# 	    for my $id (@ids) {
# 		my $url = sprintf("INDEX/%02d/h%04d/%08d.html", $id / 1000000, $id / 10000, $id);
# 		$id = sprintf("%08d", $id);
# 		$INPUT =~ s/\s/:/g;
# 		$INPUT =~ s/　/:/g;
# 		$output .= "<a href=index.cgi?URL=$url&KEYS=" 
# 		    . &uri_escape($INPUT) . " target=\"_blank\" class=\"ex\">$id</a> ",
# 		$count++;
# 		last if $count >= $PRINT_THRESHOLD;
# 	    }
#	    print $output;
	}
    }
    # フッタ出力
    print << "END_OF_HTML";
    <hr>
	<address>&copy;2006 Kurohashi Lab.</address>
	</body>
	</html>
END_OF_HTML
}    

sub decodeResult{
    my($result_str) = @_;
    my @result_ary;
    foreach (split(/\n/, $result_str)){
	my($did,$score) = split(/,/, $_);
	push(@result_ary, {"did" => $did, "score" => $score});
    }
    return \@result_ary;
}

# 検索に用いる語のみを返す
sub GetData
{
    my ($input) = @_;
    return if ($input =~ /^(\<|\@|EOS)/);
    chomp $input;

    my @w = split(/\s+/, $input);

    # 削除する条件
    return if ($w[2] =~ /^[\s*　]*$/);
    return if ($w[3] eq "助詞");
    return if ($w[5] =~ /^(句|読)点$/);
    return if ($w[5] =~ /^空白$/);
    return if ($w[5] =~ /^(形式|副詞的)名詞$/);

    return $w[2];
}
