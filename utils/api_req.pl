#!/usr/bin/env perl

# $Id$

use LWP::UserAgent;
use URI::Escape;
use Encode;
use Encode::Guess;
use utf8;
use Getopt::Long;
use strict;

my (%opt);
GetOptions(\%opt, 'query=s', 'start=i', 'results=i');

# 検索したいキーワード (utf8)をURIエンコードする
# my $encoding = guess_encoding($opt{query}, qw/ascii euc-jp shiftjis 7bit-jis utf8/)->name();
my $encoding = 'euc-jp';
Encode::from_to($opt{query}, $encoding, 'utf8');
my $uri_escaped_query = uri_escape($opt{query});

# リクエストURLを作成
my $base_url = 'http://nlpc06.ixnlp.nii.ac.jp/api.cgi';
my $results = (defined $opt{results}) ? $opt{results} : 10;
my $start = (defined $opt{start}) ? $opt{start} : 1;
my $req_url = "$base_url?query=$uri_escaped_query&results=$results&start=$start";
$req_url .= "&logical_operator=AND&dpnd=1&force_dpnd=0&no_snippets=1&result_items=Id";

# UserAgent の作成
my $ua = new LWP::UserAgent();
# Proxy の設定
$ua->proxy('http', 'http://proxy.kuins.net:8080');
# タイムアウトの設定
$ua->timeout(3600);

# リクエストの送信
my $req = HTTP::Request->new(GET => $req_url);
$req->header('Accept' => 'text/xml');
my $response = $ua->request($req);

# TSUBAKI APIの結果を取得
if ($response->is_success()) {
    my $xmldat = $response->content();
    Encode::from_to($xmldat, 'utf8', $encoding);
    $xmldat =~ s/<\?xml version="1.0" encoding="utf\-8"\?>/<\?xml version="1.0" encoding="$encoding"\?>/;
    print $xmldat;
} else {
    print STDERR "Failed to call the TSUBAKI API.\n";
}
