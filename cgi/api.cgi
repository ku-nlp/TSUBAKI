#!/home/skeiji/local/bin/perl

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
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use XML::Writer;
use XML::DOM;
use File::stat;
use POSIX qw(strftime);
use Encode qw(encode decode from_to);
use URI::Escape qw(uri_escape);
use Time::HiRes;
use utf8;
use CDB_File;
use Data::Dumper;

use SearchEngine;
use QueryParser;
use SnippetMakerAgent;

my @loadave = split(/ /, `uptime`);
chop($loadave[14]);
if($loadave[14] > 3.0){
    my $i = int(rand(10));
#   sleep(5 + $i);
}

my $cgi = new CGI;
my %params = ();
## 検索条件の初期化
$params{'ranking_method'} = 'OKAPI';
$params{'start'} = 1;
$params{'logical_operator'} = 'AND';
$params{'dpnd'} = 1;
$params{'results'} = 10;
$params{'force_dpnd'} = 0;
$params{'filter_simpages'} = 1;
$params{'only_hitcount'} = 0;
$params{'no_snippets'} = 1;
$params{'near'} = 0;

## 指定された検索条件に変更
$params{'URL'} = $cgi->param('URL') if($cgi->param('URL'));
$params{'query'} = decode('utf8', $cgi->param('query')) if($cgi->param('query'));
$params{'start'} = $cgi->param('start') if(defined($cgi->param('start')));
$params{'logical_operator'} = $cgi->param('logical') if(defined($cgi->param('logical')));
$params{'results'} = $cgi->param('results') if(defined($cgi->param('results')));
$params{'only_hitcount'} = $cgi->param('only_hitcount') if(defined($cgi->param('only_hitcount')));
$params{'force_dpnd'} = $cgi->param('force_dpnd') if(defined($cgi->param('force_dpnd')));
$params{'syngraph'} = 0;

if(defined($cgi->param('snippets'))) {
    if ($cgi->param('snippets') > 0) {
	$params{'no_snippets'} = 0;
    } else {
	$params{'no_snippets'} = 1;
    }
} else {
    $params{'no_snippets'} = 1;
}

# if($cgi->param('dpnd') == 0){
#     $params{'dpnd'} = 0;
# }

# if($cgi->param('filter_simpages') == 1){
#     $params{'filter_simpages'} = 1;
# }else{
#     $params{'filter_simpages'} = 0;
# }

$params{'query'} =~ s/^(?: | )+//g;
$params{'query'} =~ s/(?: | )+$//g;

$params{'near'} = shift(@{$cgi->{'near'}}) if ($cgi->param('near'));

my $date = `date +%m%d-%H%M%S`;
chomp ($date);
my $TOOL_HOME='/home/skeiji/local/bin';
my $ORDINARY_DFDB_PATH = '/var/www/cgi-bin/dbs/dfdbs';
my $SYNGRAPH_DFDB_PATH = '/home/skeiji/tmp';

my $KNP_PATH = $TOOL_HOME;
my $JUMAN_PATH = $TOOL_HOME;
my $SYNDB_PATH = '/home/skeiji/tmp/SynGraph/syndb/i686';

my $CACHE_PROGRAM = 'http://tsubaki.ixnlp.nii.ac.jp/index.cgi';
my $ORDINARY_SF_PATH = '/net2/nlpcf34/disk08/skeiji';
my $HTML_FILE_PATH = '/net2/nlpcf34/disk08/skeiji';
my $CACHED_PAGE_ACCESS_TEMPLATE = "cache=%09d";
my $CACHED_HTML_PATH_TEMPLATE = "/net2/nlpcf34/disk08/skeiji/h%03d/h%05d/%09d.html";
my $SF_PATH_TEMPLATE   = "/net2/nlpcf34/disk08/skeiji/x%03d/x%05d/%09d.xml";

my $MAX_NUM_OF_WORDS_IN_SNIPPET = 100;
my $TITLE_DB_PATH = '/work/skeiji/titledb';
my $URL_DB_PATH = '/work/skeiji/urldb';

my %titledbs = ();
my %urldbs = ();

# current time
my $timestamp = strftime("%Y-%m-%d %T", localtime(time));

# # utf8 encoded query
# my $query = decode('utf8', $cgi->param('query'));
# my $INPUT = $query;
my $uri_escaped_query = uri_escape(encode('utf8', $params{'query'})); # uri_escape_utf8($query);

# # number of search results
# my $result_num = $cgi->param('results');
# $result_num = 10 unless $result_num; # default number of results

# my $RANKING_METHOD = $cgi->param('rank');
# $RANKING_METHOD = 'OKAPI'; # unless $RANKING_METHOD; # default number of results

# # start position of results
# my $start_num = $cgi->param('start');
# $start_num = 1 unless $start_num;
# my $START = $start_num;
# my $PRINT_THRESHOLD = $result_num + $start_num;

# get an operation
my $file_type = $cgi->param('format');

my $field = $cgi->param('field');

# my $LOGICAL_COND = $cgi->param('logical');
# $LOGICAL_COND = 'AND' unless $LOGICAL_COND; # default number of results

# my $ANALYZE_LEVEL = $cgi->param('analyze');
# $ANALYZE_LEVEL = 'JUMAN' unless($ANALYZE_LEVEL);

# my $VERBOSE = $cgi->param('verbose');
# $VERBOSE = 'ON' unless($VERBOSE);

# my $DEP_COND = $cgi->param('dep_cond');
# $DEP_COND = 'OFF' unless($DEP_COND);

# my $SIM_PAGES = $cgi->param('filter_simpages');
# $SIM_PAGES = 0 unless($SIM_PAGES);

unless (defined $cgi->param('result_items')) {
    $params{Id} = 1;
    $params{Score} = 1;
    $params{Rank} = 1;
    $params{Url} = 1;
    $params{Snippet} = 0;
    $params{Cache} = 1;
    $params{Title} = 1;
    $params{Snippet} = 1 if ($params{'no_snippets'} < 1);
} else {
    foreach my $item_name (split(':', $cgi->param('result_items'))) {
	$params{$item_name} = 1;
    }

    $params{'no_snippets'} = 0 if (exists $params{Snippet});
}


# XML DOM Parser for acquiring information of HTML
my $parser = new XML::DOM::Parser;

if (defined $field) {
    my %request_items = ();
    foreach my $ri (split(':', $field)) {
	$request_items{$ri} = 1;
    }

    my $fid = $cgi->param('id');
    if ($fid eq '') {
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    my $query_str = $cgi->param('query');
    if ($query_str eq '') {
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータqueryの値が必要です。\n";
	exit(1);
    }

    # parse query
    my $q_parser = new QueryParser({
	KNP_PATH => $KNP_PATH,
	JUMAN_PATH => $JUMAN_PATH,
	SYNDB_PATH => $SYNDB_PATH,
	KNP_OPTIONS => ['-postprocess','-tab'] });
    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;

    my $query_obj = $q_parser->parse($query_str, {logical_cond_qk => 'AND', syngraph => 0});

    if (exists $request_items{'Snippet'}) {
	my $sni_obj = new SnippetMakerAgent();
	$sni_obj->create_snippets($query_obj, [$fid], {discard_title => 0, syngraph => 0, window_size => 5});
	my $did2snippets = $sni_obj->get_snippets_for_each_did();
	$request_items{'Snippet'} = $did2snippets->{$fid};
    }

    if (exists $request_items{'Title'}) {
	$request_items{'Title'} = &get_title($fid);
    }

    if (exists $request_items{'Url'}) {
	$request_items{'Url'} = &get_url($fid);
    }

    if (exists $request_items{'Cache'}) {
	my $cache = {
	    URL  => &get_cache_location($fid, &get_uri_escaped_query($query_obj)),
	    Size => &get_cache_size($fid) };
	$request_items{'Cache'} = $cache;
    }

    print $cgi->header(-type => 'text/xml', -charset => 'utf-8');
    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    $writer->startTag('Result', Id => sprintf("%08d", $fid));
    foreach my $ri (sort {$b cmp $a} keys %request_items) {
	$writer->startTag($ri);
	if ($ri ne 'Cache') {
	    $writer->characters($request_items{$ri}. "\n");
	} else {
	    $writer->startTag('Url');
	    $writer->characters($request_items{Cache}->{URL});
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters($request_items{Cache}->{Size});
	    $writer->endTag('Size');
	}
	$writer->endTag($ri);
    }
    $writer->endTag('Result');
} elsif ($file_type) {
    my $fid = $cgi->param('id');

    if($fid eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    if ($cgi->param('no_encoding') && $file_type ne 'xml') {
	print $cgi->header(-type => "text/$file_type");
    } else {
	print $cgi->header(-type => "text/$file_type", -charset => 'utf-8');
    }

    my $filepath;
    if ($file_type eq 'xml') {
	$filepath = sprintf("%s/x%03d/x%05d/%09d.xml", $ORDINARY_SF_PATH, $fid / 1000000, $fid / 10000, $fid);
    } elsif ($file_type eq 'html') {
	$filepath = sprintf("%s/h%03d/h%05d/%09d.html", $HTML_FILE_PATH, $fid / 1000000, $fid / 10000, $fid);
    }
    
    my $content = '';
    if (-e $filepath) {
	if ($cgi->param('no_encoding')) {
	    $content = `cat $filepath`;
	} else {
	    $content = `cat $filepath | /home/skeiji/local/bin/nkf --utf8`;
	}
    } else {
	$filepath .= ".gz";
	if (-e $filepath) {
	    if ($cgi->param('no_encoding')) {
		$content = `zcat $filepath`;
	    } else {
		$content = `zcat $filepath | /home/skeiji/local/bin/nkf --utf8`;
	    }
	}
    }
    print $content;
} else {
#    print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
#    print "ご迷惑をお掛けして申し訳ございませんが、APIサービスは現在停止しております。\n再開までしばらくお待ち下さい。\n";
#    exit(1);

    if($params{'query'} eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "queryの値を指定して下さい。\n";
	exit(1);
    }

    my $start_time = Time::HiRes::time;
    my $query_utf8 = encode('utf8', $params{'query'});
    if($params{'only_hitcount'}){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
    }else{
	print $cgi->header(-type => 'text/xml',  -charset => 'utf-8');
    }

    # parse query
    my $q_parser = new QueryParser({
	KNP_PATH => $KNP_PATH,
	JUMAN_PATH => $JUMAN_PATH,
	SYNDB_PATH => $SYNDB_PATH,
	KNP_OPTIONS => ['-postprocess','-tab'] });

    $q_parser->{SYNGRAPH_OPTION}->{hypocut_attachnode} = 1;
    
    # logical_cond_qk  クエリ間の論理演算
    my $query = $q_parser->parse($params{query}, {logical_cond_qk => $params{logical_operator}, syngraph => $params{syngraph}});
    $query->{results} = $params{results} + $params{start} - 1;
    foreach my $qk (@{$query->{keywords}}) {
	$qk->{force_dpnd} = 1 if ($params{force_dpnd});
	$qk->{logical_cond_qkw} = 'OR' if ($params{logical_operator} eq 'OR');
    }

    # 検索
    my $se_obj = new SearchEngine($params{syngraph});
    $se_obj->init($ORDINARY_DFDB_PATH);

    my $start_time = Time::HiRes::time;
    my ($hitcount, $results) = $se_obj->search($query);
    my $finish_time = Time::HiRes::time;
    my $search_time = $finish_time - $start_time;

    if ($params{'only_hitcount'}) {
	my $finish_time = Time::HiRes::time;
	my $search_time = $finish_time - $start_time;

	# ログの保存
	my $date = `date +%m%d-%H%M%S`; chomp ($date);
	open(OUT, ">> /se_tmp/input.log");
	my $param_str;
	foreach my $k (sort keys %params){
	    $param_str .= "$k=$params{$k},";
	}
	$param_str .= "hitcount=$hitcount,time=$search_time";
	print OUT "$date $ENV{REMOTE_ADDR} API $param_str\n";
	close(OUT);

	printf ("%d\n", $hitcount);
    } else {
	## merging
	my $size = $params{'start'} + $params{'results'} - 1;
	$size = $hitcount if ($hitcount < $size);
	$params{'results'} = $hitcount if ($params{'results'} > $hitcount);
		
	# 検索サーバから得られた検索結果のマージ
	my ($mg_result, $miss_title, $miss_url) = &merge_search_results($results, $size);
	$size = (scalar(@{$mg_result}) < $size) ? scalar(@{$mg_result}) : $size;

	# 検索結果の表示
	&print_search_result(\%params, $mg_result, $query, $params{'start'} - 1, $size, $hitcount);


	# ログの保存
	my $date = `date +%m%d-%H%M%S`; chomp ($date);
	open(OUT, ">> /se_tmp/input.log");
	binmode(OUT, ':utf8');
	my $param_str;
	foreach my $k (sort keys %params){
	    $param_str .= "$k=$params{$k},";
	}
	$param_str .= "hitcount=$hitcount,time=$search_time";
	$param_str .= ",miss_title=$miss_title,miss_url=$miss_url";
	print OUT "$date $ENV{REMOTE_ADDR} API $param_str\n";
	close(OUT);
    }
    
# 	my $until = $params{'start'} + $params{'results'} - 1;
# 	$until = $hitcount if($hitcount < $until);
# 	$params{'results'} = $hitcount if($params{'results'} > $hitcount);

# 	my $max = 0;
# 	my @merged_results;
# 	my %didbuff = ();

# 	while (scalar(@merged_results) < $until) {
# 	    for (my $k = 0; $k < scalar(@{$results}); $k++) {
# 		next unless (defined($results->[$k][0]));
		
# 		if ($results->[$max][0]{score} <= $results->[$k][0]{score}) {
# 		    $max = $k;
# 		}
# 	    }

# 	    if (exists($didbuff{$results->[$max][0]->{did}})) {
# 		shift(@{$results->[$max]});
# #		$until--;
# 	    } else {
# 		$didbuff{$results->[$max][0]->{did}} = 1;
# 		push(@merged_results, shift(@{$results->[$max]}));
# 	    }
# 	}
# 	my $finish_time = Time::HiRes::time;
# 	my $search_time = $finish_time - $start_time;
	
# 	# ログの保存
# 	my $date = `date +%m%d-%H%M%S`; chomp ($date);
# 	open(OUT, ">> /se_tmp/input.log");
# 	my $param_str;
# 	foreach my $k (sort keys %params){
# 	    $param_str .= "$k=$params{$k},";
# 	}
# 	$param_str .= "hitcount=$hitcount,time=$search_time";
# 	print OUT "$date $ENV{REMOTE_ADDR} API $param_str\n";
# 	close(OUT);
	
	
# 	for my $d (@{$ret_result}) {
# 	    $writer->startTag('Result', Rank => $d->{rank}, Id => sprintf("%08d", $d->{did}), Score => sprintf("%.5f", $d->{score}));
	    
# 	    $writer->startTag('Title');
# 	    if(utf8::is_utf8($d->{title})){
# 		$d->{title} = encode('utf8', $d->{title});
# 	    }

# 	    $d->{title} =~ s/\x09//g;
# 	    $d->{title} =~ s/\x0a//g;
# 	    $d->{title} =~ s/\x0b//g;
# 	    $d->{title} =~ s/\x0c//g;
# 	    $d->{title} =~ s/\x0d//g;

# 	    $writer->characters($d->{title});
# 	    $writer->endTag('Title');
	    
# 	    $writer->startTag('Url');
# 	    $writer->characters($d->{original_url});
# 	    $writer->endTag('Url');

# 	    $writer->startTag('Snippet');
# 	    $writer->characters($d->{snippet});
# 	    $writer->endTag('Snippet');
	    
# 	    $writer->startTag('Cache');
# 	    $writer->startTag('Url');
# 	    $writer->characters(&get_cache_location($d->{did}, $uri_escaped_query));
# 	    $writer->endTag('Url');
# 	    $writer->startTag('Size');
# 	    $writer->characters(&get_cache_size($d->{did}));
# 	    $writer->endTag('Size');
# 	    $writer->endTag('Cache');
	    
# 	    $writer->endTag('Result');
# 	}
	
#	$writer->endTag('ResultSet');
#	$writer->end();
#    }
}

# 装飾されたスニペットを生成する関数
sub create_snippet {
    my ($did, $query, $params) = @_;

    # snippet用に重要文を抽出
    my $sentences;
    if ($params->{'syngraph'}) {
# 	my $xmlpath = sprintf("%s/x%05d/%09d.xml", $SYNGRAPH_SF_PATH, $did / 10000, $did);
# 	unless (-e "$xmlpath.gz") {
# 	    $xmlpath = sprintf("/net2/nlpcf34/disk03/skeiji/sfs_w_syn/x%05d/%09d.xml", $did / 10000, $did);
# 	}
# 	$sentences = &SnippetMaker::extractSentencefromSynGraphResult($query->{keywords}, $xmlpath);
    } else {
	my $filepath = sprintf("%s/x%03d/x%05d/%09d.xml", $ORDINARY_SF_PATH, $did / 1000000, $did / 10000, $did);
	unless (-e $filepath || -e "$filepath.gz") {
	    $filepath = sprintf("/net2/nlpcf34/disk02/skeiji/xmls/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
	}
	$sentences = &SnippetMaker::extractSentencefromKnpResult($query->{keywords}, $filepath);
    }

    my $wordcnt = 0;
    my %snippets = ();
    # スコアの高い順に処理
    foreach my $sentence (sort {$b->{score_total} <=> $a->{score_total}} @{$sentences}) {
	my $sid = $sentence->{sid};
	for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
	    $snippets{$sid} .= $sentence->{surfs}[$i];
	    $wordcnt++;

	    # スニペットが N 単語を超えた終了
	    if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET) {
		$snippets{$sid} .= " ...";
		last;
	    }
	}
	# ★ 多重 foreach の脱出に label をつかう
	last if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET);
    }

    my $snippet;
    my $prev_sid = -1;
    foreach my $sid (sort {$a <=> $b} keys %snippets) {
	if ($sid - $prev_sid > 1 && $prev_sid > -1) {
	    $snippet .= " ... " unless ($snippet =~ /\.\.\.$/);
	}
	$snippet .= $snippets{$sid};
	$prev_sid = $sid;
    }

    $snippet =~ s/S\-ID:\d+//g;
    $snippet = encode('utf8', $snippet) if (utf8::is_utf8($snippet));

    return $snippet;
}

sub print_search_result {
    my ($params, $result, $query, $from, $end, $hitcount) = @_;

    my $did2snippets = {};
    if ($params{no_snippets} < 1 || $params{Snippet} > 0) {
	my @dids = ();
	for (my $rank = $from; $rank < $end; $rank++) {
	    push(@dids, sprintf("%09d", $result->[$rank]{did}));
	}
	my $sni_obj = new SnippetMakerAgent();
	$sni_obj->create_snippets($query, \@dids, {discard_title => 0, syngraph => $params->{'syngraph'}, window_size => 5});
	$did2snippets = $sni_obj->get_snippets_for_each_did();
    }

    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
    $writer->xmlDecl('utf-8');
    $writer->startTag('ResultSet', time => $timestamp, query => $params->{'query'}, 
		      totalResultsAvailable => $hitcount, 
		      totalResultsReturned => $end - $from, 
		      firstResultPosition => $params->{'start'},
		      logicalOperator => $params->{'logical_operator'},
		      forceDpnd => $params->{'force_dpnd'},
		      dpnd => $params->{'dpnd'},
		      filterSimpages => $params->{'filter_simpages'}
	);

    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	my $url = $result->[$rank]{url};
	my $score = $result->[$rank]{score_total};
	my $title = $result->[$rank]{title};
	
	# 装飾されたスニペッツの生成
#	my $snippet = ($params{no_snippets} < 1) ? &create_snippet($did, $query, $params) : '';

	if ($params{Score} > 0) {
	    if ($params{Id} > 0) {
		$writer->startTag('Result', Rank => $rank + 1, Id => $did, Score => sprintf("%.5f", $score));
	    } else {
		$writer->startTag('Result', Rank => $rank + 1, Score => sprintf("%.5f", $score));
	    }
	} else {
	    if ($params{Id} > 0) {
		$writer->startTag('Result', Rank => $rank + 1, Id => $did);
	    } else {
		$writer->startTag('Result', Rank => $rank + 1);
	    }
	}

	if ($params{Title} > 0) {
	    $writer->startTag('Title');

	    $title =~ s/\x09//g;
	    $title =~ s/\x0a//g;
	    $title =~ s/\x0b//g;
	    $title =~ s/\x0c//g;
	    $title =~ s/\x0d//g;

	    $writer->characters($title);
	    $writer->endTag('Title');
	}
	    
	if ($params{Url} > 0) {
	    $writer->startTag('Url');
	    $writer->characters($url);
	    $writer->endTag('Url');
	}

	if ($params{Snippet} > 0) {
	    $writer->startTag('Snippet');
	    $writer->characters($did2snippets->{$did});
	    $writer->endTag('Snippet');
	}
	    
	if ($params{Cache} > 0) {
	    $writer->startTag('Cache');
	    $writer->startTag('Url');
	    $writer->characters(&get_cache_location($did, $uri_escaped_query));
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters(&get_cache_size($did));
	    $writer->endTag('Size');
	    $writer->endTag('Cache');
	}

	$writer->endTag('Result');
    }
    $writer->endTag('ResultSet');
    $writer->end();
}

sub merge_search_results {
    my ($results, $size) = @_;

    my $max = 0;
    my $pos = 0;
    my @merged_result;
    my %url2pos = ();
    my $prev = undef;
    my $miss_title = 0;
    my $miss_url = 0;
    while (scalar(@merged_result) < $size) {
	my $flag = 0;
	for (my $i = 0; $i < scalar(@{$results}); $i++) {
	    next unless (defined $results->[$i][0]{score_total});
	    $flag = 1;
	    if ($results->[$max][0]{score_total} < $results->[$i][0]{score_total}) {
		$max = $i;
	    } elsif ($results->[$max][0]{score_total} == $results->[$i][0]{score_total}) {
		$max = $i if ($results->[$max][0]{did} < $results->[$i][0]{did});
	    }
	}
	last if ($flag < 1);

	my $did = sprintf("%09d", $results->[$max][0]{did});
	# タイトルの取得
	my $title;
	if ($results->[$max][0]{title}) {
	    $title = $results->[$max][0]{title};
	} else {
	    $miss_title++;
	    $title = &get_title($did);
	}

	# URL の取得
	my $url;
	if ($results->[$max][0]{url}) {
	    $url = $results->[$max][0]{url};
	} else {
	    $url = &get_url($did);
	    $miss_url++;
	}
	my $url_mod = &get_normalized_url($url);

	$results->[$max][0]{title} = $title;
	$results->[$max][0]{url} = $url;

	my $p = $url2pos{$url_mod};
	if (defined $p) {
	    push(@{$merged_result[$p]->{similar_pages}}, shift(@{$results->[$max]}));
	} else {
	    if (defined $prev && $prev->{title} eq $title &&
		$prev->{score} - $results->[$max][0]{score_total} < 0.05) {
		push(@{$merged_result[$pos - 1]->{similar_pages}}, shift(@{$results->[$max]}));
		$url2pos{$url_mod} = $pos - 1;
		$prev->{score} = $results->[$max][0]{score_total};
	    } else {
		$prev->{title} = $title;
		$prev->{score} = $results->[$max][0]{score_total};
		$merged_result[$pos] = shift(@{$results->[$max]});
		$url2pos{$url_mod} = $pos++;
	    }
	}
    }

    # DB の untie
    foreach my $k (keys %titledbs){
	untie %{$titledbs{$k}};
    }
    foreach my $k (keys %urldbs){
	untie %{$urldbs{$k}};
    }

    return (\@merged_result, $miss_title, $miss_url);
}

# URLの正規化
sub get_normalized_url {
    my ($url) = @_;
    my $url_mod = $url;
    $url_mod =~ s/\d+/0/g;
    $url_mod =~ s/\/+/\//g;

    my ($proto, $host, @dirpaths) = split('/', $url_mod);
    my $dirpath_mod;
    for (my $i = 0; $i < 2; $i++) {
	$dirpath_mod .= "/$dirpaths[$i]";
    }

    return uc("$host/$dirpath_mod");
}

sub get_results_specified_num {
    my ($result, $start, $until, $query) = @_;
    my @ret = ();

    my $prev_page = undef;
    for (my $i = $start; $i < $until; $i++) {
	my $did = sprintf("%09d", $result->[$i]{did});
	# タイトルの取得
	$result->[$i]->{title} = &get_title($did);
	# URL の取得
	$result->[$i]->{original_url} = &get_url($did);

	my $snippet = '';
	my %words = ();
	my $length = 0;
 	if ($params{no_snippets} < 1) {
 	    my $filepath = sprintf("/net/nlpcf2/export2/skeiji/data/xmls/x%04d/%08d.xml", $did / 10000, $did);
 	    unless (-e $filepath || -e "$filepath.gz") {
 		$filepath = sprintf("/net2/nlpcf34/disk02/skeiji/xmls/%02d/x%04d/%08d.xml", $did / 1000000, $did / 10000, $did);
 	    }

 	    ## snippet用に重要文を抽出
 	    my $sentences = &SnippetMaker::extractSentencefromKnpResult($query->{keywords}, $filepath);
 	    my $wordcnt = 0;
 	    foreach my $sentence (sort {$b->{score_total} <=> $a->{score_total}} @{$sentences}) {
 		foreach my $surf (@{$sentence->{surfs}}) {
 		    $snippet .= $surf;
 		    $wordcnt++;
		    
 		    if ($wordcnt > 100) {
 			$snippet .= " ...";
 			last;
 		    }
 		}
 		$snippet .= " ";

 		# ★ 多重 foreach の脱出に label をつかうこと
 		last if ($wordcnt > 100);
 	    }
 	}
	
	my $score = $result->[$i]->{score_total};
#	if ($prev_page->{title} eq $title && $prev_page->{score} == $score) {
#	    if ($params{'filter_simpages'}) {
#		next;
#	    }
#	} else {
#	    my $sim = 0;
# 	    if(defined($prev_page->{words})){
# 		$sim = &calculateSimilarity($prev_page->{words}, \%words);
# 	    }
#	    
# 	    $prev_page->{words} = \%words;
# 	    $prev_page->{title} = $title;
# 	    $prev_page->{score} = $score;
#	    
# 	    if($params{'filter_simpages'} && $sim > 0.9){
# 		next;
# 	    }
#	}
	
	$result->[$i]->{snippet} = encode('utf8', $snippet);
	$result->[$i]->{snippet} = encode('utf8', $snippet) if (utf8::is_utf8($snippet));
	$result->[$i]{rank} = $i + 1;
	push(@ret, $result->[$i]);
    }
    
    # DB の untie
    foreach my $k (keys %titledbs){
	untie %{$titledbs{$k}};
    }
    foreach my $k (keys %urldbs){
	untie %{$urldbs{$k}};
    }

    return \@ret;
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

sub get_cache_location {
    my ($id, $uri_escaped_query) = @_;

    my $loc = sprintf($CACHED_PAGE_ACCESS_TEMPLATE, $id);
#    return "${CACHE_PROGRAM}?loc=$loc&query=$uri_escaped_query";
    return "${CACHE_PROGRAM}?$loc&KEYS=$uri_escaped_query";
}

sub get_cache_size {
    my ($id) = @_;

    my $st = stat(sprintf($CACHED_HTML_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id) . ".gz");
    return '' unless $st;
    return $st->size;
}

sub get_file_info {
    my ($id) = @_;

    my $filename = sprintf($SF_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id);
    return '' unless -f $filename;
    my $doc = $parser->parsefile($filename);

    my $sentences = $doc->getElementsByTagName('S');
    for my $i (0 .. $sentences->getLength - 1) { # for each S
	my $sentence = $sentences->item($i);
	for my $s_child_node ($sentence->getChildNodes) {
	    if ($s_child_node->getNodeName eq 'RawString') { # one of the children of S is RawString
		for my $node ($s_child_node->getChildNodes) {
		    $doc->dispose;
		    return $node->getNodeValue; # the first one is title
		}
	    }
	}
    }

    $doc->dispose;
    return '';
}

# sub broadcastSearch{
#     my($trigram_qs, $search_qs) = @_;
#     my $trigram_qs_str = join(':',(keys %{$trigram_qs}));
#     my $search_qs_str  = join(':',(keys %{$search_qs}));
#     $trigram_qs_str = 'null' if($trigram_qs_str eq '');

#     my $selecter = IO::Select->new;
#     for(my $i = 0; $i < scalar(@HOSTS); $i++){
# 	my $host = $HOSTS[$i];
# 	my $socket = IO::Socket::INET->new(PeerAddr => $host,
# 					   PeerPort => $PORT,
# 					   Proto    => 'tcp',
# 					   );
# 	$selecter->add($socket);
# 	unless($socket){
# 	    die "$host に接続できませんでした。 $!\n";
# 	}

# 	# 文字列を送信
# 	my $str_search_q = join(":",keys %{$search_qs});
# 	my $topN = $START + $PRINT_THRESHOLD;
# 	print $socket "SEARCH,$trigram_qs_str $search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$ANALYZE_LEVEL,$DEP_COND,$topN\n";
# #	print $socket "SEARCH,$trigram_qs_str $search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$ANALYZE_LEVEL\n";
# 	$socket->flush();
#     }
    
#     # 文字列を受信
#     my @results;
#     my $hitcount = 0;
#     my $num_of_sockets = scalar(@HOSTS);
#     while($num_of_sockets > 0){
# 	my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
# 	foreach my $socket (@{$readable_sockets}){
# 	    my $buff = <$socket>;
# 	    chop($buff);
# 	    $hitcount += $buff;

# 	    $buff = <$socket>;
# 	    $buff =~ s/\[RET\]/\n/g;
# 	    push(@results, &decodeResult($buff));
		
# 	    $selecter->remove($socket);
# 	    $socket->close();
# 	    $num_of_sockets--;
# 	}
#     }
#     push(@results,$hitcount);
#     return \@results;
# }

# sub broadcastSearch2{
#     my($hosts,$port,$level,$dep_cond,$verbose,$qs) = @_;
#     my $selecter = IO::Select->new;
#     my $search_qs_str = join(":",(keys %{$qs}));
# #    print "<!-- keys " . encode('utf8',$search_qs_str) . " -->\n";
# #    print "<!-- port " . $port . " -->\n";
# #    print "<!-- level " .$level . " -->\n";

#     for(my $i = 0; $i < scalar(@{$hosts}); $i++){
# 	my $host = $hosts->[$i];
# 	my $socket = IO::Socket::INET->new(PeerAddr => $host,
# 					   PeerPort => $port,
# 					   Proto    => 'tcp',
# 					   );
# 	$selecter->add($socket);
# 	unless($socket){
# 	    die "$host に接続できませんでした。 $!\n";
# 	}
	    
# 	# 文字列を送信
# 	print $socket "SEARCH,$search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$level,$dep_cond,$PRINT_THRESHOLD\n";
# #	print "<!-- SEARCH,$search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$level -->\n";
# 	$socket->flush();
#     }
    
#     # 文字列を受信
#     my @results;
#     my $hitcount = 0;
#     my $num_of_sockets = scalar(@{$hosts});
#     while($num_of_sockets > 0){
# 	my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
# 	foreach my $socket (@{$readable_sockets}){
# 	    my $buff = <$socket>;
# 	    chop($buff);
# 	    $hitcount += $buff;
# #	    print "<!-- $hitcount -->\n";

# 	    $buff = <$socket>;
# 	    $buff =~ s/\[RET\]/\n/g;
# 	    push(@results, &decodeResult($buff));
		
# 	    $selecter->remove($socket);
# 	    $socket->close();
# 	    $num_of_sockets--;
# 	}
#     }
#     push(@results,$hitcount);
#     return \@results;
# }

sub get_title {
    my ($did) = @_;

    # タイトルの取得
    my $did_prefix = sprintf("%03d", $did / 1000000);
    my $title = $titledbs{$did_prefix}->{$did};
    unless (defined($title)) {
	my $titledbfp = "$TITLE_DB_PATH/$did_prefix.title.cdb";
	tie my %titledb, 'CDB_File', "$titledbfp" or die "$0: can't tie to $titledbfp $!\n";
	$titledbs{$did_prefix} = \%titledb;
	$title = $titledb{$did};
    }

    if ($title eq '') {
	return 'no title.';
    } else {
	return $title;
    }
}

sub get_url {
    my ($did) = @_;

    # URL の取得
    my $did_prefix = sprintf("%03d", $did / 1000000);
    my $url = $urldbs{$did_prefix}->{$did};
    unless (defined($url)) {
	my $urldbfp = "$URL_DB_PATH/$did_prefix.url.cdb";
	tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
	$urldbs{$did_prefix} = \%urldb;
	$url = $urldb{$did};
    }

    return $url;
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

sub get_uri_escaped_query {
    my ($query) = @_;
    my $uriescaped_query;
    foreach my $qk (@{$query->{keywords}}) {
	# uri escaped query の生成
	my $words = $qk->{words};
	foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @{$words}) {
	    foreach my $rep (sort {$b->{string} cmp $a->{string}} @{$reps}) {
		next if ($rep->{isContentWord} < 1 && $qk->{is_phrasal_search} < 1);

		my $mod_k = $rep->{string};
		$mod_k =~ s/\/.+$//; # 読みを削除
		if ($mod_k =~ /s\d+:/) {
		    $mod_k =~ s/s\d+://g;
		    $mod_k = "&lt;$mod_k&gt;";
		}
		$uriescaped_query .= (uri_escape(encode('utf8', $mod_k) . ":"));
	    }
	}
	$uriescaped_query =~ s/%3A$//; # 最後の : を削除
    }
    return $uriescaped_query;
}
