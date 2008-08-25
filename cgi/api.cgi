#!/home/skeiji/local/bin/perl
#!/share09/home/skeiji/local/bin/perl
#!/usr/local/bin/perl

# $Id$


use Configure;

my $CONFIG = Configure::get_instance();

# モジュールのパスを設定
BEGIN {
    $CONFIG = Configure::get_instance();
    push(@INC, $CONFIG->{TSUBAKI_MODULE_PATH});
}



# REST API for search

# Request parameters
# query   : utf8 encoded query
# results : the number of search results
# start   : start position of search results

# Output response (XML)
# ResultSet : a set of results, this field has the following attributes
#   totalResultsAvailable : the number of all results
#   totalResultsReturned  : the number of returned results
#   firstResultPosition   : start position of search results
# Result    : a result

use strict;
use utf8;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use File::stat;

# 以下TSUBAKIオリジナルクラス
use Searcher;
use Renderer;
use Logger;
use RequestParser;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;



&main();

sub main {
    my $request_method = $ENV{'REQUEST_METHOD'};

    # POST呼び出し
    # 複数文書に対する情報取得
    if ($request_method eq 'POST') {
	my $length = $ENV{'CONTENT_LENGTH'};
	my $dat;
	read(STDIN, $dat, $length);

	# 入力をパース
	my ($queryString, $requestItems, $dids, $opt) = RequestParser::parsePostRequest($dat);

	# 遅延コンストラクタ呼び出し（$ENVの値を書き換えるため）
	my $cgi = new CGI();
	print $cgi->header(-type => 'text/xml', -charset => 'utf-8');

	my $results = &getRequestItems($queryString, $requestItems, $dids, $opt);

	my $renderer = new Renderer();
	$renderer->printRequestResult($dids, $results, $requestItems, $opt);
    }
    # GET呼び出し
    else {
	# 1. 一文書に対する情報取得
	# 2. 標準フォーマット、オリジナルページ取得
	# 3. 検索結果取得

	my $cgi = new CGI();

	# 1. 一文書に対する情報取得の場合は指定される
	my $field = $cgi->param('field');
	# 2. 標準フォーマット、オリジナルページ取得の場合は指定される
	my $fileType = $cgi->param('format'); #

	# 1. 一文書に対する情報取得
	if (defined $field) {
	    # binmode(STDOUT, ':utf8');
	    # binmode(STDERR, ':utf8');

	    my $highlight = $cgi->param('highlight');
	    &provideDocumentInfo($cgi, $field, {highlight => $highlight});
	}
	# 2. 標準フォーマット、オリジナルページ取得
	elsif ($fileType) {
	    &provideDocumentData($cgi, $fileType);
	}
	# 3. 検索結果取得
	else {
	    binmode(STDOUT, ':utf8');
	    binmode(STDERR, ':utf8');

	    &provideSearchResult($cgi);
	}
    }
}

sub getRequestItems {
    my ($queryString, $requestItems, $dids, $opt) = @_;

    # スニペットが指定されている場合は取得する
    my $results;
    my $did2snippets;
    my $query_obj = undef;
    if (exists $requestItems->{'Snippet'}) {
	unless ($query_obj) {
	    # parse query
	    my $q_parser = new QueryParser({ignore_yomi => $CONFIG->{IGNORE_YOMI}});
	    $query_obj = $q_parser->parse($queryString, {logical_cond_qk => 'AND', syngraph => $opt->{syngraph}});
	}

	my $sni_obj = new SnippetMakerAgent();
	$sni_obj->create_snippets($query_obj, $dids, $opt);
	$did2snippets = ($opt->{kwic}) ? $sni_obj->makeKWICForAPICall() : $sni_obj->get_snippets_for_each_did($query_obj, {highlight => $opt->{highlight}});
    }

    my $searcher = new Searcher();
    my $renderer = new Renderer();
    # 返り値をセットする
    foreach my $fid (@$dids) {
	$results->{$fid}{'Snippet'} = $did2snippets->{$fid} if (exists $requestItems->{'Snippet'});
	if (exists $requestItems->{'Title'}) {
	    $results->{$fid}{'Title'} = $searcher->get_title($fid);
	}
	if (exists $requestItems->{'Url'}) {
	    $results->{$fid}{'Url'} = $searcher->get_url($fid);
	}

	if (exists $requestItems->{'Cache'}) {
	    unless ($query_obj) {
		# parse query
		my $q_parser = new QueryParser({ignore_yomi => $CONFIG->{IGNORE_YOMI}});
		$query_obj = $q_parser->parse($queryString, {logical_cond_qk => 'AND', syngraph => $opt->{syngraph}});
	    }

	    my $cache = {
		URL  => &get_cache_location($fid, $renderer->get_uri_escaped_query($query_obj)),
		Size => &get_cache_size($fid) };
	    $results->{$fid}{'Cache'} = $cache;
	}
    }

    return $results;
}

sub get_cache_location {
    my ($fid, $uri_escaped_query) = @_;

    my $loc = sprintf($CONFIG->{CACHED_PAGE_ACCESS_TEMPLATE}, $fid);
    return ($uri_escaped_query eq '') ? "$CONFIG->{INDEX_CGI}?$loc" : "$CONFIG->{INDEX_CGI}?$loc&KEYS=$uri_escaped_query";
}

sub get_cache_size {
    my ($fid) = @_;

    my $st = stat(sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $fid / 1000000, $fid / 10000, $fid));
    return '' unless $st;
    return $st->size;
}

sub provideDocumentInfo {
    my ($cgi, $field, $opt) = @_;

    my %requestItems = ();
    foreach my $ri (split(':', $field)) {
	$requestItems{$ri} = 1;
    }

    my $did = $cgi->param('id');
    if ($did eq '') {
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    my $queryString = $cgi->param('query');
    if (exists $requestItems{'Snippet'}) {
	if ($queryString eq '') {
	    print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	    print "パラメータqueryの値が必要です。\n";
	    exit(1);
	}
    }

    my $results = &getRequestItems($queryString, \%requestItems, [$did], $opt);

    print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
    my $renderer = new Renderer();
    $renderer->printRequestResult([$did], $results, \%requestItems, $opt);
}


sub provideDocumentData {
    my ($cgi, $fileType) = @_;

    my $did = $cgi->param('id');

    if($did eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    if ($cgi->param('no_encoding') && $fileType eq 'html') {
	print $cgi->header(-type => "text/html");
    } else {
	if ($fileType eq 'html') {
	    print $cgi->header(-type => "text/html", -charset => 'utf-8');
	} else {
	    print $cgi->header(-type => "text/xml", -charset => 'utf-8');
	}
    }

    # ファイルタイプに応じたファイルパスを取得
    my $filepath;
    if ($fileType eq 'xml_w_anchor') {
	$filepath = sprintf("%s/x%03d/x%05d/%09d.xml", $CONFIG->{ORDINARY_SF_W_ANCHOR_PATH}, $did / 1000000, $did / 10000, $did);
    } elsif ($fileType eq 'xml') {
	$filepath = sprintf("%s/x%03d/x%05d/%09d.xml", $CONFIG->{ORDINARY_SF_PATH}, $did / 1000000, $did / 10000, $did);
    } elsif ($fileType eq 'html') {
	$filepath = sprintf("%s/h%03d/h%05d/%09d.html", $CONFIG->{HTML_FILE_PATH}, $did / 1000000, $did / 10000, $did);
    }


    my $content = '';
    if (-e $filepath) {
	$content = ($cgi->param('no_encoding')) ?
	    `cat $filepath` :
	    `cat $filepath | $CONFIG->{TOOL_HOME}/nkf --utf8`;
    } else {
	$filepath .= ".gz";
	if (-e $filepath) {
	    $content = ($cgi->param('no_encoding')) ?
		`zcat $filepath` :
		`zcat $filepath | $CONFIG->{TOOL_HOME}/nkf --utf8`;
	}
    }
    print $content;
}


sub provideSearchResult {
    my ($cgi) = @_;

    my $params = RequestParser::parseAPIRequest($cgi);

    # サービス停止中
    if ($CONFIG->{SERVICE_STOP_FLAG}) {
	require Renderer;
	Renderer::printErrorMessage($cgi, $CONFIG->{MESSAGE}) if ($CONFIG->{MESSAGE});
	exit;
    }
    # クエリの値がないので終了
    elsif (!defined $params->{'query'}) {
	require Renderer;
	Renderer::printErrorMessage($cgi, 'queryの値を指定して下さい。');
	exit;
    }


    ##############################
    # クエリが入力された場合は検索
    ##############################

    my $THIS_IS_API_CALL = 1;

    # LOGGERの起動
    my $logger = new Logger($THIS_IS_API_CALL);


    # 検索クエリの構造体を取得
    my $query = RequestParser::parseQuery($params, $logger);
    $logger->setTimeAs('return_parse_query', '%.3f');

    # 検索スレーブサーバーへの問い合わせ
    my $searcher = new Searcher($THIS_IS_API_CALL);
    my ($result, $size, $status) = $searcher->search($query, $logger, $params);


    # 検索スレーブサーバーが込んでいた場合
    if ($status eq 'busy') {
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	printf qq(ただいま検索サーバーが混雑しています。時間をおいてから再検索して下さい。\n);
	exit;
    }



    # HTTPヘッダの出力
    my $type_value = ($params->{'only_hitcount'}) ? 'text/plain' : 'text/xml';
    print $cgi->header(-type => $type_value, -charset => 'utf-8');
    # print $cgi->header(-type => 'text/plain', -charset => 'utf-8');


    if ($params->{'only_hitcount'}) {
	# ヒットカウントを出力
	printf ("%d\n", $logger->getParameter('hitcount'));
    } else {
	# 検索結果の表示
	my $renderer = new Renderer(1);
	if ($params->{Cache}) {
	    foreach my $ret (@$result) {
		$ret->{cache_location} = &get_cache_location($ret->{did}, $renderer->get_uri_escaped_query($query));
		$ret->{cache_size} = &get_cache_size($ret->{did});
	    }
	}
	$renderer->printSearchResultForAPICall($params, $result, $query, $params->{'start'}, $size, $logger->getParameter('hitcount'));
    }

    $logger->setTimeAs('print_result', '%.3f');

    # LOGGERの終了
    $logger->close();
}
