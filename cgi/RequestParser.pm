package RequestParser;

# $Id$

##########################################################
# CGIパラメタ，APIアクセス時のパラメタを解析するモジュール
##########################################################

use strict;
use utf8;
use Encode;
use Configure;
use Encode::Guess;
use Dumper;


my $CONFIG = Configure::get_instance();

sub getDefaultValues {
    my ($call_from_API) = @_;
    my %params = ();

    # KWIC表示のデフォルト設定
    $params{kwic_window_size} = $CONFIG->{KWIC_WINDOW_SIZE};
    $params{num_of_pages_for_kwic_view} = 200;
    $params{use_of_repname_for_kwic} = 1;
    $params{use_of_katuyou_for_kwic} = 1;
    $params{use_of_dpnd_for_kwic} = 1;
    $params{use_of_huzokugo_for_kwic} = 0;

    # 環境変数のセット
    $params{URI} = sprintf ("%s", $ENV{REQUEST_URI});

    $params{start} = 0;
    $params{logical_operator} = 'AND';
    $params{dpnd} = 1;
    $params{results} = ($call_from_API) ? 10 : $CONFIG->{NUM_OF_SEARCH_RESULTS};
    $params{force_dpnd} = 0;
    $params{filter_simpages} = 1;
    $params{near} = -1;
    $params{syngraph} = 0;
    $params{ignore_yomi} = $CONFIG->{IGNORE_YOMI};
    $params{accuracy} = $CONFIG->{SEARCH_ACCURACY};
    $params{num_of_results_per_page} = $CONFIG->{NUM_OF_RESULTS_PER_PAGE};
    $params{only_hitcount} = 0;
    $params{distance} = 30;
    $params{sort_by} = 'score';
    $params{no_snippets} = ($call_from_API) ? 1 : 0;
    $params{query_verbose} = 0;
    $params{flag_of_dpnd_use} = 1;
    $params{flag_of_dist_use} = 1;
    $params{flag_of_anchor_use} = ($call_from_API) ? 1 : 1;
    $params{highlight} = ($call_from_API) ? 0 : 1;
    $params{develop_mode} = $CONFIG->{TEST_MODE};
    $params{antonym_and_negation_expansion} = 0;
    $params{disable_cache} = $CONFIG->{DISABLE_CACHE};
    $params{disable_synnode} = 0;
    $params{detect_requisite_dpnd} = 1;
    $params{query_filtering} = 1;
    $params{trimming} = 1;

    return \%params;
}

# POSTデータの解析
sub parsePostRequest {
    my ($dat) = @_;

    my $THIS_IS_API_CALL = 1;
    my $params = &getDefaultValues($THIS_IS_API_CALL);

    require XML::LibXML;
    # XMLデータの解析
    my $parser = new XML::LibXML;
    my $xmlreq = $parser->parse_string($dat);


    # パラメータの取得
    my $docinfo = shift @{$xmlreq->getChildNodes()};
    foreach my $attr ($docinfo->attributes()) {
	$params->{$attr->getName()} = $attr->getValue();
    }


    # 要素名の取得
    my %result_items = ();
    foreach my $ri (split(':', $docinfo->getAttribute('result_items'))) {
	$result_items{$ri} = 1;
    }


    # 文書IDの取得
    my @dids = ();
    foreach my $doc ($docinfo->getChildNodes) {
        next if ($doc->nodeName() eq '#text');

        my $did = $doc->getAttribute('Id');
        push(@dids, $did);
    }


    return ($params->{query}, \%result_items, \@dids, $params);
}

# cgiパラメタを取得
sub parseCGIRequest {
    my ($cgi) = @_;

    my $THIS_IS_API_CALL = 0;
    my $params = &getDefaultValues($THIS_IS_API_CALL);

    # $paramsの値を指定された検索条件に変更

    if ($cgi->param('cache')) {
	$params->{cache} = $cgi->param('cache');
	$params->{KEYS} = $cgi->param('KEYS');

	# cache はキャッシュされたページを表示するだけなので以下の操作は行わない
	return $params;
    }

    $params->{query} = decode('utf8', $cgi->param('q')) if ($cgi->param('q'));
    $params->{start} = $cgi->param('start') if (defined($cgi->param('start')));
    $params->{logical_operator} = $cgi->param('logical') if (defined($cgi->param('logical')));
    $params->{kwic} = $cgi->param('kwic') if (defined($cgi->param('kwic')));
    $params->{sort_by_CR} = $cgi->param('sort_by_CR') if (defined($cgi->param('sort_by_CR')));
    $params->{num_of_pages_for_kwic_view} = $cgi->param('num_of_pages_for_kwic_view') if (defined($cgi->param('num_of_pages_for_kwic_view')));
    $params->{highlight} = $cgi->param('highlight') if (defined($cgi->param('highlight')));
    $params->{kwic_window_size} = $CONFIG->{KWIC_WINDOW_SIZE};

    $params->{from_portal} = $cgi->param('from_portal') if (defined($cgi->param('from_portal')));

    $params->{develop_mode} = $cgi->param('develop_mode') if (defined($cgi->param('develop_mode')));
    # $params->{develop_mode} = 1 if ($CONFIG->{INDEX_CGI} =~ /develop/);
    $params->{score_verbose} = $params->{develop_mode};
    $params->{debug} = $cgi->param('debug') if (defined($cgi->param('debug')));

    $params->{antonym_and_negation_expansion} = $cgi->param('antonym_and_negation_expansion') if (defined($cgi->param('antonym_and_negation_expansion')));
    $params->{use_of_case_analysis} = 0;
    $params->{use_of_NE_tagger} = 1;
    $params->{disable_cache} = 1 if (defined($cgi->param('disable_cache')));
    $params->{query_filtering} = 1;

    &normalize_logical_operator($params);

    $params->{syngraph} = 1;
    $params->{disable_synnode} = ($cgi->param('disable_synnode') eq 'on') ? 1 : 0;

    # クエリに制約(近接およびフレーズ)が指定されていなければ~100wをつける
    if ($params->{query} !~ /~/ && $params->{query} ne '' &&
	$params->{query} !~ /^"/ && $params->{query} !~ /"$/) {
	$params->{query} .= '~100w'
    }

    return $params;
}


sub parseAPIRequest {
    my ($cgi) = @_;

    my $THIS_IS_API_CALL = 1;
    my $params = &getDefaultValues($THIS_IS_API_CALL);

    # 検索結果に含める文書情報の取得
    if (defined $cgi->param('result_items')) {
	foreach my $item_name (split(':', $cgi->param('result_items'))) {
	    $params->{$item_name} = 1;
	}
	$params->{'no_snippets'} = 0 if (exists $params->{Snippet});
    } else {
	$params->{Id} = 1;
	$params->{Score} = 1;
	$params->{Rank} = 1;
	$params->{Url} = 1;
	$params->{Cache} = 1;
	$params->{Title} = 1;
	$params->{Snippet} = ($params->{'snippets'} == 1 || $params->{'no_snippets'} < 1) ? 1 : 0;
    }

    # 指定された検索条件に変更
    my $recievedString = $cgi->param('query') if ($cgi->param('query'));
    my $encoding = guess_encoding($recievedString, qw/ascii euc-jp shiftjis 7bit-jis utf8/); # range
    unless ($encoding =~ /utf8/) {
	unless ($recievedString =~ /^(\p{Latin}|\p{Common})+$/) {
	    require Renderer;
	    Renderer::printErrorMessage($cgi, 'queryの値はutf8でエンコードした文字列を指定して下さい。');
	    exit(1);
	}
    }

    $params->{'query'} = decode('utf8', $recievedString);
    $params->{'query'} =~ s/^(?: | )+//g;
    $params->{'query'} =~ s/(?: | )+$//g;

    $params->{'logical_operator'} = $cgi->param('logical') if (defined($cgi->param('logical')));
    $params->{'logical_operator'} = $cgi->param('logical_operator') if (defined($cgi->param('logical_operator')));
    $params->{'only_hitcount'} = $cgi->param('only_hitcount') if (defined($cgi->param('only_hitcount')));
    $params->{'force_dpnd'} = $cgi->param('force_dpnd') if (defined($cgi->param('force_dpnd')));

    $params->{'syngraph'} = 1;
    $params->{'disable_synnode'} = ($cgi->param('syngraph') == 1) ? 0 : 1;

    $params->{'sort_by'} = $cgi->param('sort_by') if (defined($cgi->param('sort_by')));
    $params->{'near'} = $cgi->param('near') if (defined $cgi->param('near'));
    $params->{'filter_simpages'} = 0 if (defined $cgi->param('filter_simpages') &&  $cgi->param('filter_simpages') eq '0');
    $params->{query_verbose} = $cgi->param('query_verbose') if (defined($cgi->param('query_verbose')));
    $params->{flag_of_anchor_use} = $cgi->param('anchor') if (defined($cgi->param('anchor')));
    $params->{highlight} = $cgi->param('highlight') if (defined($cgi->param('highlight')));
    $params->{antonym_and_negation_expansion} = (defined($cgi->param('antonym_and_negation_expansion'))) ? $cgi->param('antonym_and_negation_expansion') : 0;
    $params->{use_of_case_analysis} = 1 if (defined($cgi->param('use_of_case_analysis')));
    $params->{disable_cache} = 1 if (defined($cgi->param('disable_cache')));
    $params->{query_filtering} = 1;

    $params->{kwic} = $cgi->param('kwic') if (defined($cgi->param('kwic')));
    $params->{kwic_window_size} = (defined($cgi->param('kwic_window_size'))) ? $cgi->param('kwic_window_size') : $CONFIG->{KWIC_WINDOW_SIZE};
    $params->{use_of_repname_for_kwic} = $cgi->param('use_of_repname_for_kwic') if (defined($cgi->param('use_of_repname_for_kwic')));
    $params->{use_of_katuyou_for_kwic} = $cgi->param('use_of_katuyou_for_kwic') if (defined($cgi->param('use_of_katuyou_for_kwic')));

    if (defined($cgi->param('snippets'))) {
	$params->{'no_snippets'} = ($cgi->param('snippets') > 0) ? 0 : 1;
	$params->{'Snippet'} = 1;
    } else {
	$params->{'no_snippets'} = 1;
    }

    # 取得する検索件数の設定
    if (defined($cgi->param('start'))) {
	$params->{start} = $cgi->param('start') - 1;
	if ($params->{start} < 0) {
	    require Renderer;
	    Renderer::printErrorMessage($cgi, 'startの値は1以上を指定して下さい.');
	    exit(1);
	}
    }

    if (defined($cgi->param('results'))) {
	$params->{results} = $cgi->param('results');
	if ($params->{results} < 1) {
	    require Renderer;
	    Renderer::printErrorMessage($cgi, 'resultsの値は1以上を指定して下さい.');
	    exit(1);
	}
    }

    if ($params->{query} =~ //) {
	
    }

    return $params;
}


sub normalize_logical_operator {
    my ($params) = @_;

    if ($params->{logical_operator} eq 'DPND_AND') {
	$params->{force_dpnd} = 1;
	$params->{dpnd} = 1;
	$params->{logical_operator} = 'AND';
    } else {
	if ($params->{logical_operator} eq 'WORD_AND') {
	    $params->{logical_operator} = 'AND';
	}
	$params->{force_dpnd} = 0;
	$params->{dpnd} = 1;
    }
}

# 検索クエリを解析する
sub parseQuery {
    my ($params, $logger) = @_;

    # クエリのログをとる
    $logger->setParameterAs('query', $params->{query}) if ($logger);

    my $DFDB_DIR = ($params->{syngraph} > 0) ? $CONFIG->{SYNGRAPH_DFDB_PATH} : $CONFIG->{ORDINARY_DFDB_PATH};
    my $q_parser = new QueryParser({ DFDB_DIR => $DFDB_DIR,
				     ignore_yomi => $CONFIG->{IGNORE_YOMI},
				     use_of_case_analysis => $params->{use_of_case_analysis},
				     use_of_NE_tagger => $params->{use_of_NE_tagger},
				     debug => $params->{debug}
				   });

    if ($params->{debug}) {
	while (my ($k, $v) = each %$q_parser) {
	    if ($k eq 'INDEXER' || $k eq 'KNP') {
		print Dumper::dump_as_HTML($v) . "<br>\n";
		print "<hr>\n";
	    }
	}
    }

    # クエリの解析
    # logical_cond_qk: クエリ間の論理演算
    my $query = $q_parser->parse(
	$params->{query},
	{ logical_cond_qk => $params->{logical_operator},
	  syngraph => $params->{syngraph},
	  near => $params->{near},
	  trimming => $params->{trimming},
	  antonym_and_negation_expansion => $params->{antonym_and_negation_expansion},
	  detect_requisite_dpnd => $params->{detect_requisite_dpnd},
 	  query_filtering => $params->{query_filtering},
	  disable_dpnd => $params->{disable_dpnd},
	  disable_synnode => $params->{disable_synnode}
	});

    # 取得ページ数のセット
    $query->{results} = $params->{results};

    # 取得ページの精度をセット
    $query->{accuracy} = $params->{accuracy};


    # 実際に検索スレーブサーバーに要求する件数を求める

    # 検索サーバーの台数を取得
    my $N = ($query->{syngraph}) ? scalar(@{$CONFIG->{SEARCH_SERVERS_FOR_SYNGRAPH}}) : scalar(@{$CONFIG->{SEARCH_SERVERS}});
    my $alpha = ($query->{results} > 5000) ? 1.5 : 30 * ($query->{results}**(-0.34));
    my $M = $query->{results} / $N;
    $query->{results} = int(1 + $M * $alpha);
    $query->{results} = 1000 if ($CONFIG->{NTCIR_MODE});
    $logger->setParameterAs('request_results_for_slave_server', $query->{results}) if ($logger);

    # 係り受けと近接のスコアを考慮するようにする
    $query->{flag_of_dpnd_use} = $params->{flag_of_dpnd_use};
    $query->{flag_of_dist_use} = $params->{flag_of_dist_use};
    $query->{flag_of_anchor_use} = $params->{flag_of_anchor_use};

    # スコアの詳細が必要かどうか
    $query->{score_verbose} = $params->{score_verbose};

    # start をセット
    $query->{start} = $params->{start};

    # distance をセット
    $query->{DISTANCE} = $params->{distance};

    # 検索語にインターフェースより得られる検索制約を追加
    foreach my $qk (@{$query->{keywords}}) {
	$qk->{force_dpnd} = 1 if ($params->{force_dpnd});
	$qk->{logical_cond_qkw} = 'OR' if ($params->{logical_operator} eq 'OR');
    }

    # クエリ解析時間のログをとる
    $logger->setTimeAs('parse_query', '%.3f') if ($logger);

    # ポータルからのアクセスかどうかのログをとる
    $logger->setParameterAs('portal', $params->{from_portal}) if ($logger);

    return $query;
}

1;
