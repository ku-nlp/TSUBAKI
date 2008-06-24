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
	my $id = $params->{'cache'};
	my $file = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id / 1000000, $id / 10000, $id);

	# KEYごとに色を付ける
	my $query = decode('utf8', $params->{'KEYS'});

	push(@INC, $CONFIG->{WWW2SF_PATH});
	require CachedHTMLDocument;
	
	# キャッシュされたページを表示
	my $cachedHTML = new CachedHTMLDocument($query, { file => $file, z => 1 });
	print $cachedHTML->to_string();
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
	    # use Dumper;
	    # print Dumper::dump_as_HTML($query) . "<br>\n";


	    # 検索スレーブサーバーへの問い合わせ
	    my $searcher = new Searcher(0);
	    my ($results, $size, $status) = $searcher->search($query, $logger, $params);


	    # 検索結果の表示
	    $params->{query} =~ s/~100w$//g;
	    $renderer->printSearchResultForBrowserAccess($params, $results, $query, $logger, $status);


	    # LOGGERの終了
	    $logger->close();
	}
    }
}
