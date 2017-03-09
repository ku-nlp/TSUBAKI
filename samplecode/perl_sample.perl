#!/usr/bin/env perl

use LWP::UserAgent;
use URI::Escape;
use Encode;
use utf8;
use strict;

# 検索したいキーワード (utf8)をURIエンコードする
my $query = encode('utf8', '京都の観光名所');
# 検索キーワードをURLエンコーディングする
my $uri_escaped_query = uri_escape($query);

# リクエストURLを作成
my $base_url = 'http://tsubaki.ixnlp.nii.ac.jp/api.cgi';
my $results = 20;
my $start = 1;
my $req_url = "$base_url?query=$uri_escaped_query&results=$results&start=$start";

# UserAgent の作成
my $ua = new LWP::UserAgent();
# タイムアウトの設定
$ua->timeout(3600);

# リクエストの送信
my $req = HTTP::Request->new(GET => $req_url);
$req->header('Accept' => 'text/xml');
my $response = $ua->request($req);

# TSUBAKI APIの結果を取得
if ($response->is_success()) {
     print $response->content();
} else {
     print STDERR "Failed to call the TSUBAKI API.\n";
 }

