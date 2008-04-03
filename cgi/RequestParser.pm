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
    my %params = ();

    $params{start} = 0;
    $params{logical_operator} = 'WORD_AND';
    $params{dpnd} = 1;
    $params{results} =  $CONFIG->{NUM_OF_SEARCH_RESULTS};
    $params{force_dpnd} = 0;
    $params{filter_simpages} = 1;
    $params{near} = 0;
    $params{syngraph} = 0;
    $params{accuracy} = $CONFIG->{SEARCH_ACCURACY};
    $params{num_of_results_per_page} = $CONFIG->{NUM_OF_RESULTS_PER_PAGE};
    $params{only_hitcount} = 0;
    $params{distance} = 30;
    $params{snippet} = 1;

    return \%params;
}

# cgiパラメタを取得
sub parseCGIRequest {
    my ($cgi) = @_;

    my $params = &getDefaultValues();

    # $paramsの値を指定された検索条件に変更

    if ($cgi->param('cache')) {
	$params->{cache} = $cgi->param('cache');
	$params->{KEYS} = $cgi->param('KEYS');

	# cache はキャッシュされたページを表示するだけなので以下の操作は行わない
	return $params;
    }

    $params->{query} = decode('utf8', $cgi->param('INPUT')) if ($cgi->param('INPUT'));
    $params->{start} = $cgi->param('start') if (defined($cgi->param('start')));
    $params->{logical_operator} = $cgi->param('logical') if (defined($cgi->param('logical')));

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

    $params->{syngraph} = 1 if ($cgi->param('syngraph'));

    return $params;
}

1;
