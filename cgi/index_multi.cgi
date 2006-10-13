#!/share/usr/bin/perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use Retrieve;
use Encode;

use IO::Socket;
use IO::Select;

my $cgi = new CGI;
my $URL = $cgi->param('URL');
my $INPUT = $cgi->param('INPUT');
my $RANKING_METHOD = $cgi->param('rank');
my $date = `date +%m%d-%H%M%S`;
chomp ($date);

my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", 
	     "880000", "00aa00", "886800", "004699", "990099");


my $retrieve_script_dir = '/usr/local/apache/htdocs/SearchEngine/scripts/';
my $INDEX_dir = '/share3/text/WWW/tau060911';
my $PRINT_THRESHOLD = 1000;

unless(@ARGV){
    for(my $i = 1; $i < 24; $i++){
	if($i > 9){
	    push(@ARGV, "nlpc$i");
	}else{
	    push(@ARGV, "nlpc0$i");
	}
    }
}

#my @hosts = @ARGV;
my $port = 9684;

#my $retrieve = new Retrieve($INDEX_dir);

# HTTPヘッダ出力
print header(-charset => 'euc-jp');

# 指定されたＵＲＬの表示       
if ($URL) {

    my $color;
    my $html = `nkf -e $URL`;
    
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
    print 
	start_form,
	"入力: ",
	textfield(-name => 'INPUT'),
	submit('送信'),
	reset('リセット'),
	end_form,
	hr, "\n";
    
    # 入力があった場合
    if ($INPUT) {
	
	# ログの保存
	open(OUT, ">> input.log");
	print OUT "$date $ENV{REMOTE_ADDR}\t$INPUT\n";
	close OUT;
	
	my $hitcount = 0;
	my $doclinks = "";
	my $selecter = IO::Select->new;

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
	    print $socket "$INPUT,$RANKING_METHOD\n";
	    $socket->flush();
	}
	
	# 文字列を受信
	my $num_of_sockets = scalar(@hosts);
	while($num_of_sockets > 0){
	    my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	    foreach my $socket (@{$readable_sockets}){
		my $buff = <$socket>;
		chop($buff);
		$hitcount += $buff;
		
		$buff = <$socket>;
		$buff =~ s/\[RET\]/\n/g;
		$doclinks .= "$buff<hr>\n";
#		print "受信メッセージ:\n$buff";
		
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
# 	    my @ids = map({$_->{did}} @result);

 	    print "$hitcount個のファイルが見つかりました<BR>";
# 	    print $#ids + 1 . "個のファイルが見つかりました<BR>";
 	    print "最初の${PRINT_THRESHOLD}件を表示します<BR>" if $hitcount > $PRINT_THRESHOLD;
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
	    print $doclinks;
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
