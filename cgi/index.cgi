#!/home/skeiji/local/bin/perl

# $Id$

use strict;
use utf8;
use Encode;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);

# 以下TSUBAKIオリジナルクラス
use Configure;
use Searcher;
use Renderer;
use Logger;
use QueryParser;
use RequestParser;


my $CONFIG = Configure::get_instance();

&main();

sub main {
    # cgiパラメタの取得
    my $params = RequestParser::parseCGIRequest(new CGI());

    # HTTPヘッダ出力
    # print header(-type => 'text/plain', -charset => 'utf-8');
    print header(-charset => 'utf-8');

    if ($params->{'cache'}) {
	# キャッシュページの出力
	&print_cached_page($params);
    } else {
	my $renderer = new Renderer(0);

	binmode(STDOUT, ':utf8');
	binmode(STDERR, ':utf8');

	$params->{query} = undef if ($CONFIG->{SERVICE_STOP_FLAG});
	unless ($params->{query}) {
	    # TSUBAKI のトップ画面を表示
	    $renderer->print_tsubaki_interface_init($params);
	}
	# クエリが入力された場合は検索
	else {
	    # LOGGERの起動
	    my $logger = new Logger(0);


	    # 検索クエリの構造体を取得
	    my $query = RequestParser::parseQuery($params, $logger);


	    # 検索スレーブサーバーへの問い合わせ
	    my $searcher = new Searcher(0);
	    my ($results, $size, $status) = $searcher->search($query, $logger, $params);


	    # 検索結果の表示
	    $renderer->printSearchResultForBrowserAccess($params, $results, $query, $logger, $status);


	    # LOGGERの終了
	    $logger->close();
	}
    }
}


# キャッシュされたページを表示
sub print_cached_page {
    my ($params) = @_;

    my $color;
    my $id = $params->{'cache'};
    my $htmlfile = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id / 1000000, $id / 10000, $id);
    my $htmldat = decode('utf8', `gunzip -c  $htmlfile | $CONFIG->{TOOL_HOME}/nkf -w`);

    if ($htmldat =~ /(<meta [^>]*content=[" ]*text\/html[; ]*)(charset=([^" >]+))/i) {
	my $fwd = $1;
	my $match = $2;
	$htmldat =~ s/$fwd$match/${fwd}charset=utf\-8/;
    }

    # KEYごとに色を付ける
    my @KEYS = split(/:/, decode('utf8', $params->{'KEYS'}));
    print "<DIV style=\"padding:1em; background-color:#f1f4ff; border-top:1px solid gray; border-bottom:1px solid gray;\"><U>次のキーワードがハイライトされています:&nbsp;";
    foreach my $key (@KEYS) {
	next unless ($key);

	print "<span style=\"background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];\">";
	print encode('utf8', $key) . "</span>&nbsp;";
	if($color > 4){
	    # background-color が暗いので foreground-color を白に変更
	    $htmldat =~ s/$key/<span style="color:white; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$key<\/span>/g;
	}else{
	    $htmldat =~ s/$key/<span style="background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$key<\/span>/g;
	}
	$color = (++$color%scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
    }
    print "</U></DIV>";
    print encode('utf8', $htmldat);
}
