package RequestParser;

# $Id$

##########################################################
# CGIパラメタ，APIアクセス時のパラメタを解析するモジュール
##########################################################

use strict;
use utf8;
use Encode;
use Configure;


my $CONFIG = Configure::get_instance();

sub getDefaultValues {
    my ($call_from_API) = @_;
    my %params = ();

    # 環境変数のセット
    $params{URI} = sprintf ("%s", $ENV{REQUEST_URI});
    $params{num_of_pages_for_kwic_view} = 200;

    $params{start} = 0;
    $params{logical_operator} = 'AND';
    $params{dpnd} = 1;
    $params{results} = ($call_from_API) ? 10 : $CONFIG->{NUM_OF_SEARCH_RESULTS};
    $params{force_dpnd} = 0;
    $params{filter_simpages} = 1;
    $params{near} = -1;
    $params{syngraph} = 0;
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

    return \%params;
}

# POSTデータの解析
sub parsePostRequest {
    my ($dat) = @_;

    require XML::LibXML;
    my $parser = new XML::LibXML;
    my $xmlreq = $parser->parse_string($dat);

    my $docinfo = shift @{$xmlreq->getChildNodes()};

    my @dids = ();
    my $query = $docinfo->getAttribute('query');
    my $highlight = $docinfo->getAttribute('highlight');
    my %result_items = ();
    foreach my $ri (split(':', $docinfo->getAttribute('result_items'))) {
	$result_items{$ri} = 1;
    }

    foreach my $doc ($docinfo->getChildNodes) {
        next if ($doc->nodeName() eq '#text');

        my $did = $doc->getAttribute('Id');
        push(@dids, $did);
    }

    return ($query, \%result_items, \@dids, {highlight => $highlight});
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

    &normalize_logical_operator($params);

    $params->{syngraph} = 1 if ($cgi->param('syngraph'));

    # クエリに制約が指定されていなければ~100Wをつける
    if ($params->{query} !~ /~/ && $params->{query} ne '') {
	$params->{query} .= '~100W'
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
    $params->{'query'} = decode('utf8', $cgi->param('query')) if ($cgi->param('query'));
    $params->{'query'} =~ s/^(?: | )+//g;
    $params->{'query'} =~ s/(?: | )+$//g;

    $params->{'logical_operator'} = $cgi->param('logical') if (defined($cgi->param('logical')));
    $params->{'only_hitcount'} = $cgi->param('only_hitcount') if (defined($cgi->param('only_hitcount')));
    $params->{'force_dpnd'} = $cgi->param('force_dpnd') if (defined($cgi->param('force_dpnd')));
    $params->{'syngraph'} = $cgi->param('syngraph') if (defined($cgi->param('syngraph')));
    $params->{'sort_by'} = $cgi->param('sort_by') if (defined($cgi->param('sort_by')));
    $params->{'near'} = $cgi->param('near') if (defined $cgi->param('near'));
    $params->{'filter_simpages'} = 0 if (defined $cgi->param('filter_simpages') &&  $cgi->param('filter_simpages') eq '0');
    $params->{query_verbose} = $cgi->param('query_verbose') if (defined($cgi->param('query_verbose')));
    $params->{flag_of_anchor_use} = $cgi->param('anchor') if (defined($cgi->param('anchor')));
    $params->{highlight} = $cgi->param('highlight') if (defined($cgi->param('highlight')));
    $params->{kwic} = $cgi->param('kwic') if (defined($cgi->param('kwic')));

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
    $logger->setParameterAs('query', $params->{query});

    my $DFDB_DIR = ($params->{syngraph} > 0) ? $CONFIG->{SYNGRAPH_DFDB_PATH} : $CONFIG->{ORDINARY_DFDB_PATH};
    my $q_parser = new QueryParser({ DFDB_DIR => $DFDB_DIR });

    # クエリの解析
    # logical_cond_qk: クエリ間の論理演算
    my $query = $q_parser->parse($params->{query}, {logical_cond_qk => $params->{logical_operator}, syngraph => $params->{syngraph}, near => $params->{near}});

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
    $logger->setParameterAs('request_results_for_slave_server', $query->{results});

    # 係り受けと近接のスコアを考慮するようにする
    $query->{flag_of_dpnd_use} = $params->{flag_of_dpnd_use};
    $query->{flag_of_dist_use} = $params->{flag_of_dist_use};
    $query->{flag_of_anchor_use} = $params->{flag_of_anchor_use};

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
    $logger->setTimeAs('parse_query', '%.3f');

    return $query;
}

1;
