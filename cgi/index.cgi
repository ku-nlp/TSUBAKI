#!/home/skeiji/local/bin/perl

# $Id$

use Configure;

my $CONFIG;
# モジュールのパスを設定
BEGIN {
    $CONFIG = Configure::get_instance();
    push(@INC, $CONFIG->{TSUBAKI_SCRIPT_PATH});
    push(@INC, $CONFIG->{TSUBAKI_MODULE_PATH});
    push(@INC, $CONFIG->{UTILS_PATH});
}

use strict;
use utf8;
use Encode;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);

# 以下TSUBAKIオリジナルクラス
use Searcher;
use Renderer;
use Logger;
use QueryParser;
use RequestParser;
use Dumper;



&main();

sub main {
    # HTTPヘッダ出力
    print header(-charset => 'utf-8');

    # cgiパラメタの取得
    my $params = RequestParser::parseCGIRequest(new CGI());


    if ($params->{debug}) {
	print Dumper::dump_as_HTML($CONFIG);
	print "<HR>\n";
    }

    if ($params->{'cache'}) {
	# キャッシュページの出力
	my $id = $params->{'cache'};
	my $file;
	if ($CONFIG->{IS_KUHP_MODE}) {
	    $file = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id);
	}
	elsif ($CONFIG->{IS_NICT_MODE}) {
	    my $did_w_version = $id;
	    my ($did) = ($did_w_version =~ /(^\d+)/);
	    $file = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id / 1000000, $id / 1000, $did_w_version);
	}
	elsif ($CONFIG->{IS_IPSJ_MODE}) {
 	    $file = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id);
 	}
	else {
	    $file = sprintf($CONFIG->{CACHED_HTML_PATH_TEMPLATE}, $id / 1000000, $id / 10000, $id);
	}

	# KEYごとに色を付ける
	my $query = decode('utf8', $params->{'KEYS'});

	push(@INC, $CONFIG->{WWW2SF_PATH});
	require CachedHTMLDocument;

	# キャッシュされたページを表示
	my $cachedHTML = new CachedHTMLDocument($query, { file => $file, debug => $params->{debug} });
	if ($CONFIG->{IS_KUHP_MODE}) {
	    my $htmldata = $cachedHTML->to_string();
	    my ($findings) = ($htmldata =~ m!<DIV myblocktype="findings">(.+?)</DIV>!);
	    my ($imp)      = ($htmldata =~ m!<DIV myblocktype="imp">(.+?)</DIV>!);
	    my ($order)    = ($htmldata =~ m!<DIV myblocktype="order">(.+?)</DIV>!);

	    print "<HTML><BODY><TABLE border=1><TR><TH>Findings</TH><TH>Imp.</TH><TH>Order</TH></TR>\n";

	    print "<TR>\n";
	    foreach my $text (($findings, $imp, $order)) {
		print "<TD valign=top>\n";
		print "<UL>\n";
		foreach my $line (split (/。/, $text)) {
		    print "<LI>$line。</LI>\n";
		}
		print "</UL>\n";
		print "</TD>\n";
	    }
	    print "</TR>\n";

	    print "</TABLE><BODY></HTML>";
	}
	elsif ($CONFIG->{IS_IPSJ_MODE}) {
	    print $cachedHTML->to_string_for_ipsj();
	} else {
	    print $cachedHTML->to_string();
	}
    } elsif ($params->{'did'}) {
	# 論文のメタ情報を表示（論文検索用）
	if ($CONFIG->{IS_IPSJ_MODE}) {
	    my $type = $params->{'type'};

	    if ($type eq 'meta') {
		tie my %metadb, 'CDB_File', $CONFIG->{IPSJ_METADB_PATH} or die $! . "\n";
		my $metadata = $metadb{$params->{'did'}};

		my $renderer = new Renderer(0);
		$renderer->printIPSJMetadata($metadata);

		untie %metadb;
	    }
	}
    } else {
	my $renderer = new Renderer(0);

	binmode(STDOUT, ':utf8');
	binmode(STDERR, ':utf8');

	$params->{query} = undef if ($CONFIG->{SERVICE_STOP_FLAG});
	unless (defined $params->{query}) {
	    # TSUBAKI のトップ画面を表示
	    $renderer->print_initial_display($params);
	}
	# クエリが入力された場合は検索
	else {
	    # LOGGERの起動
	    my $logger = new Logger(0);


	    # 検索クエリの構造体を取得
	    my $query = RequestParser::parseQuery($params, $logger);
	    if ($params->{debug}) {
		$query->{keywords}[0]->print_for_web() if (defined $query->{keywords}[0]);

		print "<hr>\n";
		print Dumper::dump_as_HTML($query) . "<br>\n";
		print "<hr>\n";
	    }


	    # 検索スレーブサーバーへの問い合わせ
	    my $searcher = new Searcher(0);
	    my ($results, $size, $status) = $searcher->search($query, $logger, $params);


	    # 検索結果の表示
	    $params->{query} =~ s/~100w$//g;
	    $renderer->printSearchResultForBrowserAccess($params, $results, $query, $logger, $status);


	    # LOGGERの終了
	    $logger->close();


# 	    print "<hr>\n";
# 	    print Dumper::dump_as_HTML($params) . "<br>\n";
# 	    print "<hr>\n";
	}
    }
}
