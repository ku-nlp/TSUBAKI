#!/share09/home/skeiji/local/bin/perl

# $Id$

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

# 以下TSUBAKIオリジナルクラス
use Configure;
use Searcher;
use Renderer;
use Logger;
use RequestParser;


my $CONFIG = Configure::get_instance();

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
	my ($queryString, $requestItems, $dids) = RequestParser::parsePostRequest($dat);

	my $requestItems = &getRequestItems($queryString, $requestItems, $dids);

	# 遅延コンストラクタ呼び出し（$ENVの値を書き換えるため）
	my $cgi = new CGI();
	print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
	my $renderer = new Renderer();
	$renderer->printRequestResult($dids, $requestItems);
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
	    &provideDocumentInfo($cgi);
	}
	# 2. 標準フォーマット、オリジナルページ取得
	elsif ($fileType) {
	    &provideDocumentData($cgi);
	}
	# 3. 検索結果取得
	else {
	    &provideSearchResult($cgi);
	}
    }
}

sub getRequestItems {
    my ($queryString, $requestItems, $dids) = @_;

    # スニペットが指定されている場合は取得する
    my $did2snippets;
    my $query_obj = undef;
    if (exists $requestItems->{'Snippet'}) {
	unless ($query_obj) {
	    # parse query
	    my $q_parser = new QueryParser();
	    $query_obj = $q_parser->parse($queryString, {logical_cond_qk => 'AND', syngraph => 0});
	}

	my $sni_obj = new SnippetMakerAgent();
	$sni_obj->create_snippets($query_obj, $dids, {discard_title => 0, syngraph => 0, window_size => 5});
	$did2snippets = $sni_obj->get_snippets_for_each_did();
    }

    # 返り値をセットする
    foreach my $fid (@$dids) {
	$requestItems->{$fid}{'Snippet'} = $did2snippets->{$fid} if (exists $requestItems->{'Snippet'});
	$requestItems->{$fid}{'Title'} = &get_title($fid) if (exists $requestItems->{'Title'});
	$requestItems->{$fid}{'Url'} = &get_url($fid) if (exists $requestItems->{'Url'});

	if (exists $requestItems->{'Cache'}) {
	    my $cache = {
		URL  => &get_cache_location($fid, &get_uri_escaped_query($query_obj)),
		Size => &get_cache_size($fid) };
	    $requestItems->{$fid}{'Cache'} = $cache;
	}
    }
}


sub provideDocumentInfo {
    my ($cgi, $field) = @_;

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
    if ($queryString eq '') {
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータqueryの値が必要です。\n";
	exit(1);
    }

    my $requestItems = &getRequestItems($queryString, \%requestItems);

    print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
    my $renderer = new Renderer();
    $renderer->printRequestResult([$did], $requestItems);
}


sub provideDocumentData {
    my ($cgi, $fileType) = @_;

    my $did = $cgi->param('id');

    if($did eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    if ($cgi->param('no_encoding') && $fileType ne 'xml') {
	print $cgi->header(-type => "text/$fileType");
    } else {
	print $cgi->header(-type => "text/$fileType", -charset => 'utf-8');
    }

    # ファイルタイプに応じたファイルパスを取得
    my $dir;
    if ($fileType eq 'xml_w_anchor') {
	$dir = $CONFIG->{ORDINARY_SF_W_ANCHOR_PATH};
    } elsif ($fileType eq 'xml') {
	$dir = $CONFIG->{ORDINARY_SF_PATH};
    } elsif ($fileType eq 'html') {
	$dir = $CONFIG->{HTML_FILE_PATH};
    }
    my $filepath = sprintf("%s/h%03d/h%05d/%09d.html", $dir, $did / 1000000, $did / 10000, $did);


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
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print $CONFIG->{MESSAGE}  . "\n" if ($CONFIG->{MESSAGE});
	exit;
    }
    # クエリの値がないので終了
    elsif($params->{'query'} eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "queryの値を指定して下さい。\n";
	exit;
    }


    ##############################
    # クエリが入力された場合は検索
    ##############################

    my $THIS_IS_API_CALL = 1;

    # HTTPヘッダの出力
    my $type_value = ($params->{'only_hitcount'}) ? 'text/plain' : 'text/xml';
    print $cgi->header(-type => $type_value, -charset => 'utf-8');
    # print $cgi->header(-type => 'text/plain', -charset => 'utf-8');


    # LOGGERの起動
    my $logger = new Logger($THIS_IS_API_CALL);


    # 検索クエリの構造体を取得
    my $query = RequestParser::parseQuery($params, $logger);
    $logger->setTimeAs('return_parse_query', '%.3f');

    # 検索スレーブサーバーへの問い合わせ
    my $searcher = new Searcher($THIS_IS_API_CALL);
    my ($result, $size) = $searcher->search($query, $logger, $params);


    if ($params->{'only_hitcount'}) {
	# ヒットカウントを出力
	printf ("%d\n", $logger->getParameter('hitcount'));
    } else {
	# 検索結果の表示
	my $renderer = new Renderer();
	$renderer->printSearchResultForAPICall($params, $result, $query, $params->{'start'}, $size, $logger->getParameter('hitcount'));
    }

    $logger->setTimeAs('print_result', '%.3f');

    # LOGGERの終了
    $logger->close();
}
