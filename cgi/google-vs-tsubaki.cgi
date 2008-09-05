#!/home/skeiji/local/bin/perl

# $Id$

use Configure;
use File::Basename;

my $CONFIG;
# モジュールのパスを設定
BEGIN {
    $CONFIG = Configure::get_instance();
    push(@INC, $CONFIG->{TSUBAKI_MODULE_PATH});
    my $DIRNAME = dirname($INC{'Configure.pm'});
    push(@INC, "$DIRNAME/../scripts");
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
use GoogleRaw;
use Storable;
use URI::Escape;

my $DATE = `date +%y%m%d-%H%M%S`; chomp ($DATE);
my $WORKSPACE_PREFIX = '/home/skeiji/tsubaki-develop/google-compare';
my $SCRIPT_DIR = '/home/skeiji/tsubaki-develop/SearchEngine/cgi/wget';
my $WORKSPACE = sprintf("%s/%s-%s", $WORKSPACE_PREFIX, $DATE, $$);
my $WGET_SHELL = sprintf("%s/wget-shell.sh %s", $WORKSPACE);
my $MKSF_SHELL = '/home/skeiji/cvs/WWW2sf/tool/www2sf.sh -S 52428800';
my $EMBD_SHELL = '/home/skeiji/cvs/WWW2sf/tool/scripts/test-embed-annotation.sh -s';
my $MKIDX_SHELL = '/home/skeiji/tsubaki-develop/SearchEngine/scripts/make-index-dynamic.sh';
my $SEARCH_SHELL = '/home/skeiji/tsubaki-develop/SearchEngine/scripts/search.sh';
my $LOGFILE = "$WORKSPACE/log";
my $CACHE_LOG = '/home/skeiji/tsubaki-develop/google-compare/cache';


`mkdir -p $WORKSPACE`;

$| = 1;


&main();

sub main {
    # cacheデータのロード
    my $cache = &loadCacheData();

    # cgiパラメタの取得
    my $cgi = new CGI();
    my %params = ();
    my $CGI_NAME = 'http://nlpc06.ixnlp.nii.ac.jp/cgi-bin/tsubaki-develop/google-compare.cgi';
    my $flag = 0;
    foreach my $name ($cgi->param()) {
	$flag = 1;
	$params{$name} = $cgi->param($name);

	if ($name eq 'query') {
	    $params{query} = decode('utf8', $params{$name});
	}
    }
    
    print header(-charset => 'utf-8');


    print << "END_OF_HTML";
    <HTML>
	<HEAD>
	<TITLE>検索結果比較ツール</TITLE>
	<script type="text/javascript" src="javascript/tsubaki.js"></script>
	</HEAD>
	<BODY>
	<H3>Googleとの検索結果比較ツール</H3>
	<FORM name="inputform" method="GET" action="$CGI_NAME">
	<TABLE border="0">
	<TR><TD><!-- クエリ: --></TD><TD><INPUT type="text" name="query" value="$params{query}" size="60">　<INPUT type="submit" value="検索する"/>&nbsp;
END_OF_HTML
    if ($flag) {
	my $uri_escaped_query = uri_escape(encode('utf8', $params{query}));
	my $google_url = "http://www.google.co.jp/search\?ie=UTF-8&q=$uri_escaped_query&num=10&start=0";
	print qq(<A target="_blank" style="font-size: small;" href="$google_url">Googleの結果へ</A>&nbsp;);
	print qq(<A target="_blank" style="font-size: small;" href="http://tsubaki.ixnlp.nii.ac.jp/index.cgi?start=0&q=$uri_escaped_query">TSUBAKIの結果へ</A>);
}
    print "</TD></TR>\n";
    print qq(<TR><TD><!-- 取得件数：--></TD><TD><INPUT type="hidden" name="google_num" value="6" size="5"></TD></TR>\n);

    print << "END_OF_HTML";
	</TABLE>
	</FORM>
END_OF_HTML

    my @pages;
    if ($flag) {
	if (exists $cache->{$params{query}}) {
	    $WORKSPACE = $cache->{$params{query}};
	    @pages = &loadPages($WORKSPACE);
	} else {
	    my $google = new GoogleRaw({debug_google => 0});
	    @pages = $google->search($params{query}, $params{google_num}, 0);

	    my $did = 1;
	    open (WRITER, "> $WGET_SHELL") or die $!;
	    printf WRITER ("mkdir -p %s/h\n", $WORKSPACE);
	    foreach my $p (@pages) {
		$p->{did} = $did;
		if ($did <= $params{google_num}) {
		    unless ($p->{url} =~ /(ppt|pdf)$/) {
			printf WRITER (qq(wget -U "Mozilla/4.0" -O %s/h/%09d.html "%s"\n), $WORKSPACE, $did, $p->{cache});
		    }
		}
		$did++;
	    }
	    close (WRITER);

	    &saveCacheData($WORKSPACE, $params{query}, \@pages);

	    print "* Now downloading html files...";
	    system "sh $WGET_SHELL > /dev/null 2>> $LOGFILE";
	    print "done.<br>\n";

	    `mkdir -p $WORKSPACE/x`;
	    print "* Now making simple standard format data...";
	    system "source /home/skeiji/.bashrc ; sh $MKSF_SHELL $WORKSPACE/h $WORKSPACE/x > /dev/null 2>>  $LOGFILE";
	    print "done.<br>\n";

	    `mkdir -p $WORKSPACE/s`;
	    print "* Now analyzing sentences by JUMAN, KNP and SYNGRAPH...";
	    system "source /home/skeiji/.bashrc ; sh $EMBD_SHELL $WORKSPACE/x $WORKSPACE/s > /dev/null 2>>  $LOGFILE";
	    print "done.<br>\n";

	    `mkdir -p $WORKSPACE/i`;
	    print "* Now indexing files...";
	    system "source /home/skeiji/.bashrc ; sh $MKIDX_SHELL $WORKSPACE/s $WORKSPACE/i > /dev/null 2>> $LOGFILE";
	    print "done.<br>\n";
	}

	print qq(<H4 style="padding-left:0.5em; background-color: black; color: white;"><A name="google">Google</A></H4>\n);

	my $params = RequestParser::parseCGIRequest(new CGI());
	$params->{query} .= "~OR";
	my $logger = new Logger(0);
	my $query = RequestParser::parseQuery($params, $logger);
	my $searcher = new Searcher(0, 1,
				    {
					syngraph => 1,
					idxdir => $WORKSPACE,
					dlengthdbdir => $WORKSPACE,
					verbose => 0,
					dlengthdbdir => $WORKSPACE,
					score_verbose => 1,
					logging_query_score => 1,
					dpnd_on => 1,
					dist_on => 1
				    });
	
	$query->{flag_of_anchor_use} = 0;
	$query->{score_verbose} = 1;
	$params->{score_verbose} = 1;
	$query->{DIST} = 30;
	$params->{'filter_simpages'} = 0;
	my ($results, $size, $status) = $searcher->search($query, $logger, $params);

#	print &Dumper::dump_as_HTML($query) . "\n";

	my %did2info = ();
	foreach my $p (@$results) {
	    $did2info{$p->{did}} = $p;
	}

	foreach my $p (@pages) {
	    $p->{sortKey} = -1 * $p->{did};
#	    $p->{sortKey} = ($params{sort} eq 'tsubaki') ? $did2info{$p->{did}}{score_total} : -1 * $p->{did};
#	    $p->{sortKey} = 0 unless (defined ($p->{sortKey}));
	}

	my $rank = 1;
	print qq(<TABLE width="100%">\n);
	foreach my $p (sort {$b->{sortKey} <=> $a->{sortKey}} @pages) {
	    my $did = $p->{did};
	    my $url = $p->{url};
	    my $title = $p->{title};
	    my $cache = $p->{cache};
	    my $snippet = $p->{snippet};
	    my $filetype = 'html';
	    $filetype = $1 if ($url =~ /(ppt|pdf)$/);

	    my $score_detail = &makeScoreDetail($query, $did2info{$did}, $did, 'google', $filetype);

	    print << "END_OF_HTML";
		<TR>
		<TD valign="top">$did</TD>
		<TD width="50%" valign="top" style="padding-right: 1em;">
		<A target="_blank" href="$cache">$title</A><BR>
		<BLOCKQUOTE style="margin-left: 0em; font-size: small;">$snippet</BLOCKQUOTE>
		</TD>
		<TD valign="top">
		$score_detail
		</TD>
		</TR>
END_OF_HTML
		$rank++;
	}
	print "</TABLE>\n";




	print qq(<H4 style="padding-left:0.5em; background-color: black; color: white;"><A name="tsubaki">TSUBAKI</A></H4>\n);

	$params->{query} =~ s/~OR$//;
	my $query = RequestParser::parseQuery($params, $logger);

	$query->{score_verbose} = 1;
	$params->{score_verbose} = 1;
	$query->{DIST} = 30;
	$params->{'filter_simpages'} = 1;
	$params->{'disable_cache'} = 0;
	$query->{'logging_query_score'} = 1;
	$query->{flag_of_anchor_use} = 1;
	$query->{results} = 100;

 	# 検索クエリの解析結果を表示
#  	foreach my $qk (@{$query->{keywords}}) {
#  	    $qk->print_for_web();
#  	}

	my $searcher = new Searcher(0);
	my ($results, $size, $status) = $searcher->search($query, $logger, $params);
	my $renderer = new Renderer(0);
	my $did2snippets = $renderer->get_snippets($params, $results, $query, 0, $params{google_num});

	my $uri_escaped_search_keys = $renderer->get_uri_escaped_query($query);
	my $num = ($size < $params{google_num}) ? $size : $params{google_num};
	print qq(<TABLE style="padding-left: 0em;">\n);
	for (my $i = 0; $i < $num; $i++) {
	    my $did = sprintf("%09d", $results->[$i]{did});
	    my $url = $results->[$i]{url};
	    my $title = $results->[$i]{title};
	    my $score = $results->[$i]{score_total};
	    my $snippet = $did2snippets->{$did};
	    my $filetype = $results->[$i]{filetype};

	    my $score_detail = &makeScoreDetail($query, $results->[$i], $did, 'tsubaki', 'html');

	    my $cache_url = qq(http://tsubaki.ixnlp.nii.ac.jp/index.cgi?cache=$did&KEYS=) . $uri_escaped_search_keys;
	    print qq(<TR><TD valign="top">) . ($i + 1) . qq(</TD><TD width="50%" valign="top" style="padding-right: 1em;"><A target="_blank" href="$cache_url">$title</A>&nbsp;<BR>\n);
	    print qq(<BLOCKQUOTE style="margin-left: 0em; font-size: small;">$snippet</BLOCKQUOTE>\n);
	    print qq(</TD><TD valign="top">$score_detail</TD></TR>\n);
	}
	print "</TABLE>\n";
    }

    print "</BODY></HTML>\n";
}

sub makeScoreDetail {
    my ($query, $dinfo, $did, $prefix, $filetype) = @_;

    if ($filetype ne 'html') {
	return "HTMLファイルではありません。\n";
    }

    # print &Dumper::dump_as_HTML($dinfo) . "<hr>\n";

    my $open_label = "詳細を表示";
    my $close_label = "詳細を隠す";

    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die "$!";

    my $q2score = $dinfo->{q2score};
    my $score_w = $dinfo->{score_word};
    my $score_d = $dinfo->{score_dpnd};
    my $score_n = $dinfo->{score_dist};
    my $score_aw = $dinfo->{score_word_anchor};
    my $score_ad = $dinfo->{score_dpnd_anchor};
    my $total = $dinfo->{score_total};

    my $rawstrings = sprintf qq(score=%.2f (w=%.2f,d=%.2f,n=%.2f,aw=%.2f,ad=%.2f) <SMALL><A href="javascript:void(0);" onclick="toggle_simpage_view('${prefix}_$did', this, '$open_label', '$close_label');">$open_label</A></SMALL>\n), $total, $score_w, $score_d, $score_n, $score_aw, $score_ad;

    $rawstrings .= qq(<DIV style="padding: 1em 0em 1em 0.5em;"><SMALL><B>含まれる係り受け：</B>);
    foreach my $T ('dpnd', 'near') {
	foreach my $gid (sort keys %{$q2score->{$T}}) {
	    my $score = $q2score->{$T}{$gid}{score};
	    my @qids = @{$query->{gid2qids}{$gid}};

	    foreach my $qid (@qids) {
		my $synid = $query->{qid2rep}{$qid};
		$synid =~ s/\-\>/→/;
		$rawstrings .= sprintf("%s&nbsp;(%.2f)&nbsp;", $synid, $score);
		last;
	    }
	}
    }
    $rawstrings .= "</SMALL></DIV>";

    $rawstrings .= sprintf qq(<TABLE id="${prefix}_$did" border="1" width="100%" style="display: none;">\n);
    $rawstrings .= sprintf "<TR><TH>gid</TH><TH>スコア</TH><TH>SYNノード</TH><TH>パックされている表現</TH></TR>\n";
    foreach my $T ('dpnd', 'near', 'word') {
	foreach my $gid (sort keys %{$q2score->{$T}}) {
	    my $score = $q2score->{$T}{$gid}{score};
	    my @qids = @{$query->{gid2qids}{$gid}};
	    my $size = scalar(@qids);

	    my $flag = 0;
	    $rawstrings .= sprintf qq(<TR><TD rowspan="$size">%s</TD><TD rowspan="$size">%.3f</TD>), $gid, $score;
	    foreach my $qid (@qids) {
		my $synid = $query->{qid2rep}{$qid};
		if ($T eq 'word') {
		    my $raws = join("<BR>", split(/\|/, decode('utf8', $synonyms{$synid})));
		    $rawstrings .= sprintf "<TR>" if ($flag);
		    $rawstrings .= sprintf "<TD>%s</TD><TD>%s</TD></TR>\n", $synid, $raws;
		    $flag = 1;
		} else {
		    $rawstrings .= sprintf "<TD>%s</TD><TD>\n</TD></TR>\n", $synid;
		}
	    }
	}
    }
    $rawstrings .= sprintf "</TABLE>\n";

    return $rawstrings;
}


sub loadCacheData {
    my %cache = ();

    open (READER, '<:utf8', $CACHE_LOG);
    while (<READER>) {
	chop;

	my ($k, $v) = split(/ /, $_);
	$cache{$k} = $v;
    }
    close (READER);

    return \%cache;
}

sub saveCacheData {
    my ($workspace, $k, $pages) = @_;

    open (WRITER, '>>:utf8', $CACHE_LOG);
    print WRITER $k . ' ' . $workspace . "\n";
    close (WRITER);

    store($pages, "$workspace/pages.bin") or die $!;
}

sub loadPages {
    my ($workspace) = @_;

    my $pages = retrieve("$workspace/pages.bin") or die "$!\n";

    return @$pages;
}
