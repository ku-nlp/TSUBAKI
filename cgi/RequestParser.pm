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
use IO::Socket;
use IO::Select;
use MIME::Base64;
use Storable;
use URI::Escape;


my $CONFIG = Configure::get_instance();

sub getDefaultValues {
    my ($call_from_API) = @_;

    my %params = ();

    # 環境変数のセット
    $params{URI} = sprintf ("%s", $ENV{REQUEST_URI});


    # KNPのオプション
    # 格解析を行うオプションが有効または係り受け素性を使うなら格解析を行う (日本語)
    $params{use_of_case_analysis} = $CONFIG->{USE_OF_CASE_ANALYSIS_FOR_QUERY_PROCESS} || (!$CONFIG->{IS_ENGLISH_VERSION} & $CONFIG->{USE_OF_DPND_FEATURES});
    $params{use_of_NE_tagger} = $CONFIG->{USE_OF_NE_FOR_QUERY_PROCESS};


    # 検索条件のデフォルト設定
    $params{query} = undef;
    $params{start} = 0;
    $params{logical} = 'AND';
    $params{logical_operator} = $params{logical};
    $params{dpnd} = 1;
    $params{results} = ($call_from_API) ? 10 : $CONFIG->{NUM_OF_SEARCH_RESULTS};
    $params{force_dpnd} = 0;
    $params{filter_simpages} = ($CONFIG->{IS_NICT_MODE}) ? 1 : 0;
    $params{near} = -1;
    $params{syngraph} = 1;
    $params{only_hitcount} = 0;
    $params{distance} = 30;
    $params{flag_of_dpnd_use} = 1;
    $params{flag_of_dist_use} = 1;
    $params{flag_of_pagerank_use} = ($CONFIG->{DISABLE_PAGERANK}) ? 0 : 1;
    $params{weight_of_tsubaki_score} = $CONFIG->{WEIGHT_OF_TSUBAKI_SCORE};
    $params{c_pagerank} = $CONFIG->{C_PAGERANK};
    $params{anchor} = ($CONFIG->{DISABLE_ANCHOR_INDEX}) ? 0 : 1;
    $params{flag_of_anchor_use} = $params{anchor};
    $params{disable_synnode} = 0;
    $params{detect_requisite_dpnd} = 1;
    $params{query_filtering} = 1;
    $params{trimming} = 1;
    $params{antonym_and_negation_expansion} = 0;
    $params{hypernym_expansion} = 0;
    $params{disable_query_processing} = 0;
    $params{telic_process} = $CONFIG->{USE_OF_TELIC_FOR_QUERY_PROCESS};
    $params{CN_process} = 1;
    $params{NE_process} = $CONFIG->{USE_OF_NE_FOR_QUERY_PROCESS};
    $params{modifier_of_NE_process} = $CONFIG->{USE_OF_NE_FOR_QUERY_PROCESS};
    $params{site} = undef;
    $params{blockTypes} = undef;
    $params{remove_synids} = undef;
    $params{term_states} = undef;
    $params{dpnd_states} = undef;
    $params{disable_Zwhitespace_delimiter} = 0;
    $params{call_from_api} = $call_from_API;
    $params{rawstring_max_num} = 5 unless $params{rawstring_max_num};

    # 英語用
    $params{lemma} = 0;

    # スニペット表示のデフォルト設定
    $params{no_snippets} = ($call_from_API) ? 1 : 0;
    $params{highlight} = ($call_from_API) ? 0 : 1;


    # KWIC表示のデフォルト設定
    $params{kwic} = 0;
    $params{kwic_window_size} = $CONFIG->{KWIC_WINDOW_SIZE};
    $params{num_of_pages_for_kwic_view} = 200;
    $params{use_of_repname_for_kwic} = 1;
    $params{use_of_katuyou_for_kwic} = 1;
    $params{use_of_dpnd_for_kwic} = 1;
    $params{use_of_huzokugo_for_kwic} = 0;
    $params{use_of_negation_for_kwic} = 1;
    $params{serverLog} = 0;
    $params{field} = "";
    $params{id} = -1;
    $params{Sids} = "";


    # クラスタリング結果用設定
    $params{cluster_id} = undef;
    $params{cluster_label} = undef;
    $params{org_referer} = sprintf ("%s", $ENV{REQUEST_URI});
    $params{escaped_org_referer} = uri_escape($params{org_referer});


    # その他
    $params{develop_mode} = $CONFIG->{DEVELOP_MODE};
    $params{ignore_yomi} = $CONFIG->{IGNORE_YOMI};
    $params{disable_cache} = $CONFIG->{DISABLE_CACHE};
    $params{verbose} = 0;
    $params{query_verbose} = 0;
    $params{get_basic_phrase_num_of_query} = 0;
    $params{sort_by} = 'score';
    $params{sort_by_CR} = 0;
    $params{score_verbose} = 0;
    $params{tarball} = 0;
    $params{get_jscode_for_parse_result} = 0;
    $params{use_of_anaphora_resolution} = 0;


    # NICT用 TSUBAKI用スコアとページランクの値の内訳を表示
    $params{detail_score} = 0;
    $params{debug} = 0;
    $params{result_items} = 'Id:Title:Cache:Url';
    $params{show_search_time} = 0;


    #######################################################
    # 情報爆発デモ用
    #######################################################

    # 根拠サーチ用パラメータ
    $params{conjunctive_particle} = undef;

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
    my %sids = ();
    foreach my $doc ($docinfo->getChildNodes) {
        next if ($doc->nodeName() eq '#text');

        my $did = $doc->getAttribute('Id');
	foreach my $sid (split(',', $doc->getAttribute('Sids'))) {
	    $sids{$did}->{$sid} = 1;
	}

        push(@dids, $did);
    }


    return ($params->{query}, \%result_items, \@dids, \%sids, $params);
}



sub setParametersOfGetRequest {
    my ($cgi, $params, $THIS_IS_API_CALL) = @_;

    my %types;
    foreach my $name ($cgi->param()) {
	if (exists $params->{$name}) {
	    my @values = $cgi->param($name);

	    # エイリアスの対処
	    $name = 'logical_operator' if ($name eq 'logical');
	    $name = 'flag_of_anchor_use' if ($name eq 'anchor');

	    # 指定された値で上書き
	    if ($name eq 'blockTypes') {
		# 初期化
		foreach my $tag (keys %{$CONFIG->{BLOCK_TYPE_DATA}}) {
		    $CONFIG->{BLOCK_TYPE_DATA}{$tag}{isChecked} = 0;
		}

		foreach my $tag (@values) {
		    $types{$tag} = 1;
		    $CONFIG->{BLOCK_TYPE_DATA}{$tag}{isChecked} = 1;
		}
	    }
	    # 情報爆発用デモ
	    # 根拠サーチ用パラメータの取得
	    elsif ($name eq 'conjunctive_particle') {
		foreach my $conj (split (/,/, decode('utf8', $cgi->param($name)))) {
		    push (@{$params->{$name}}, $conj);
		}
	    }
	    elsif ($name eq 'remove_synids') {
		foreach my $synids (split (/,/, decode('utf8', $cgi->param($name)))) {
		    $params->{$name}{$synids} = 1;
		}
	    }
	    elsif ($name eq 'term_states') {
		foreach my $state (split (/,/, decode('utf8', $cgi->param($name)))) {
		    my ($qid, $term_group_id, $v) = split ("=", $state);
		    $params->{$name}{$qid}{$term_group_id} = $v;
		}
	    }
	    elsif ($name eq 'dpnd_states') {
		foreach my $state (split (/,/, decode('utf8', $cgi->param($name)))) {
		    my ($qid, $term_group_id, $v) = split ("=", $state);
		    $params->{$name}{$qid}{$term_group_id} = $v;
		}
	    }
	    else {
		if (scalar (@values) > 1) {
		    $params->{$name} = \@values;
		} else {
		    $params->{$name} = shift @values;
		}
	    }

	    if ($name ne 'query') {
		$params->{$name} = 1 if ($params->{$name} eq 'on');
		$params->{$name} = 0 if ($params->{$name} eq 'off');
	    }
	} else {
	    # 未定義のパラメータが指定された
	    if ($THIS_IS_API_CALL) {
		require Renderer;
		Renderer::printErrorMessage($cgi, "不正なパラメータ($name)が設定されています。設定を解除してから再度アクセスをお願いします。");
		exit(1);
	    } else {
		# ブラウザアクセスの場合は無視
	    }
	}
    }

    if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
	unless (%types) { # 指定されていないときはdefaultのblocktype
	    foreach my $tag (keys %{$CONFIG->{BLOCK_TYPE_DATA}}) {
		$types{$tag} = 1 if $CONFIG->{BLOCK_TYPE_DATA}{$tag}{isChecked};
	    }
	}
    }
    else {
	$types{''} = 1;
    }
    $params->{blockTypes} = \%types;


    ######################################
    # パラメータの値が不正でないかチェック
    ######################################

    # クエリのエンコーディング
    my $recievedString = $params->{query};
    if (defined $recievedString && $recievedString ne '') {
	my $encoding = guess_encoding($recievedString, qw/ascii euc-jp shiftjis 7bit-jis utf8/);
	if ($encoding =~ /utf8/) {
	    $params->{query} = decode('utf8', $recievedString);
	} else {
	    unless ($recievedString =~ /^(\p{Latin}|\p{Common})+$/) {
		require Renderer;
		Renderer::printErrorMessage($cgi, 'queryの値はutf8でエンコードした文字列を指定して下さい。');
		exit(1);
	    }
	}

	# クエリ文字列中の「<」「>」「&」をエスケープする
	$params->{query} =~ s/&/&amp;/g;
	$params->{query} =~ s/</&lt;/g;
	$params->{query} =~ s/>/&gt;/g;
    } else {
	# undef, '' の場合は、index.cgi, api.cgiでそれぞれエラーを出力する
	$params->{query} = undef;
    }
    $params->{no_use_of_Zwhitespace_as_delimiter} = $params->{disable_Zwhitespace_delimiter};


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
	$params->{results} = 100000000 if ($params->{results} eq 'all');
	if ($params->{results} < 1) {
	    require Renderer;
	    Renderer::printErrorMessage($cgi, 'resultsの値は1以上を指定して下さい.');
	    exit(1);
	}
	# startの分を考慮する
	$params->{results} += $params->{start};
    }


    $params->{query} =~ s/\n$//;
    if ($params->{query} =~ /\n|\r/) {
	require Renderer;
	Renderer::printErrorMessage($cgi, 'queryの値に制御コードが含まれています。');
	exit(1);
    }
}



# cgiパラメタを取得
sub parseCGIRequest {
    my ($cgi) = @_;

    my $THIS_IS_API_CALL = 0;

    my $params = &getDefaultValues($THIS_IS_API_CALL);

    if ($cgi->param('cache')) {
	$params->{cache} = $cgi->param('cache');
	$params->{KEYS} = $cgi->param('KEYS');

	# cache はキャッシュされたページを表示するだけなので以下の操作は行わない
	return $params;
    }


    # $paramsの値を指定された検索条件に変更
    &setParametersOfGetRequest($cgi, $params, $THIS_IS_API_CALL);

    &normalize_logical_operator($params);

    return $params;
#     $params->{query} = decode('utf8', $cgi->param('q')) if ($cgi->param('q'));
#     $params->{start} = $cgi->param('start') if (defined($cgi->param('start')));
#     $params->{logical_operator} = $cgi->param('logical') if (defined($cgi->param('logical')));
#     $params->{kwic} = $cgi->param('kwic') if (defined($cgi->param('kwic')));
#     $params->{sort_by_CR} = $cgi->param('sort_by_CR') if (defined($cgi->param('sort_by_CR')));
#     $params->{num_of_pages_for_kwic_view} = $cgi->param('num_of_pages_for_kwic_view') if (defined($cgi->param('num_of_pages_for_kwic_view')));
#     $params->{highlight} = $cgi->param('highlight') if (defined($cgi->param('highlight')));
#     $params->{kwic_window_size} = $CONFIG->{KWIC_WINDOW_SIZE};

#     $params->{from_portal} = $cgi->param('from_portal') if (defined($cgi->param('from_portal')));

#     $params->{develop_mode} = $cgi->param('develop_mode') if (defined($cgi->param('develop_mode')));
#     $params->{score_verbose} = $params->{develop_mode};
#     $params->{debug} = $cgi->param('debug') if (defined($cgi->param('debug')));

#     $params->{antonym_and_negation_expansion} = $cgi->param('antonym_and_negation_expansion') if (defined($cgi->param('antonym_and_negation_expansion')));
#     $params->{use_of_case_analysis} = 0;
#     $params->{use_of_NE_tagger} = 1;
#     $params->{disable_cache} = 1 if (defined($cgi->param('disable_cache')));
#     $params->{query_filtering} = 1;
#     $params->{syngraph} = 1;
#     $params->{disable_synnode} = ($cgi->param('disable_synnode') eq 'on') ? 1 : 0;
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

    # $paramsの値を指定された検索条件に変更
    &setParametersOfGetRequest($cgi, $params, $THIS_IS_API_CALL);

    if (defined($cgi->param('snippets'))) {
	$params->{'no_snippets'} = ($cgi->param('snippets') > 0) ? 0 : 1;
	$params->{'Snippet'} = 1;
    } else {
	$params->{'no_snippets'} = 1;
    }

    if (defined $cgi->param('verbose')) {
	$params->{'verbose'} = 1;
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
	$params->{dpnd} = 1;
    }
}

# 検索クエリを解析する
sub parseQuery {
    my ($params, $logger) = @_;

    # クエリのログをとる
    $logger->setParameterAs('query', $params->{query}) if ($logger);

    my $query;
    if ($CONFIG->{USE_OF_QUERY_PARSE_SERVER}) {
	my $selecter = IO::Select->new();
	my $socket = IO::Socket::INET->new(
	    PeerAddr => $CONFIG->{HOST_OF_QUERY_PARSE_SERVER},
	    PeerPort => $CONFIG->{PORT_OF_QUERY_PARSE_SERVER},
	    Proto    => 'tcp' );

	$selecter->add($socket) or die "Cannot connect to the " . $CONFIG->{HOST_OF_QUERY_PARSE_SERVER} . " " . $CONFIG->{PORT_OF_QUERY_PARSE_SERVER} . ". $!\n";

 	# クエリ解析時のパラメータを送信
 	print $socket encode_base64(Storable::nfreeze($params), "") . "\n";
	print $socket "EOD\n";
	$socket->flush();


	# クエリ解析結果の受信
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	foreach my $socket (@{$readable_sockets}) {
	    my $buff = undef;
	    while (<$socket>) {
		last if ($_ eq "EOL\n");
		$buff .= $_;
	    }
	    if (defined($buff)) {
		my $logger2 = Storable::thaw(decode_base64($buff));
		foreach my $k ($logger2->keys()) {
		    $logger->setParameterAs($k, $logger2->getParameter($k));
		}
	    }

	    $buff = '';
	    while (<$socket>) {
		last if ($_ eq "EOD\n");
		$buff .= $_;
	    }
	    if (defined($buff)) {
		$query = Storable::thaw(decode_base64($buff));
	    }

	    # ソケットの後処理
	    $selecter->remove($socket);
	    $socket->close();
	}
#	my $qkstring = $query->{s_exp};
#	$qkstring =~ s/\n/<BR>/g;
#	$qkstring =~ s/ /&nbsp;/g;
#	print $qkstring . "\n";
    } else {
	my $q_parser = new QueryParser({
	    DFDB_DIR => ($params->{DFDB_DIR}) ? $params->{DFDB_DIR} : $CONFIG->{SYNGRAPH_DFDB_PATH},
	    ignore_yomi => $CONFIG->{IGNORE_YOMI},
	    use_of_case_analysis => $params->{use_of_case_analysis},
	    use_of_NE_tagger => $params->{use_of_NE_tagger},
	    debug => $params->{debug},
	    option => $params
	});

	if ($params->{debug}) {
	    while (my ($k, $v) = each %$q_parser) {
		if ($k eq 'INDEXER' || $k eq 'KNP') {
		    print Dumper::dump_as_HTML($v) . "<br>\n";
		    print "<hr>\n";
		}
	    }
	}

	# set parameters
	$params->{logger} = $logger;
	$params->{logical_cond_qk} = $params->{logical_operator};

	# クエリの解析
	# logical_cond_qk: クエリ間の論理演算
	$query = $q_parser->parse($params->{query}, $params);
    }

    # クエリ解析時間のログをとる
    $logger->setParameterAs('parse_query', sprintf ("%.3f",
			    $logger->getParameter('new_syngraph') +
			    $logger->getParameter('set_params_for_qks') +
			    $logger->getParameter('make_qks'))) if ($logger);

    # 取得ページ数のセット
    $query->{results} = $params->{results};


    # 以下の処理はSearcher行き
    # 実際に検索スレーブサーバーに要求する件数を求める

    # 検索サーバーの台数を取得
    if ($query->{results} > 100) {
	my $N = scalar(@{$CONFIG->{SEARCH_SERVERS}});
	my $alpha = ($query->{results} > 5000) ? 1.5 : 30 * ($query->{results}**(-0.34));
	my $M = $query->{results} / $N;

	$query->{results} = int(1 + $M * $alpha);
    }
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

    # PageRankを利用するかどうか
    $query->{flag_of_pagerank_use} = $params->{flag_of_pagerank_use};
    $query->{WEIGHT_OF_TSUBAKI_SCORE} = $params->{weight_of_tsubaki_score};
    $query->{C_PAGERANK} = $params->{c_pagerank};

    # 検索語にインターフェースより得られる検索制約を追加
    foreach my $qk (@{$query->{keywords}}) {
	$qk->{force_dpnd} = 1 if ($params->{force_dpnd});
    }

    return $query;
}

1;
