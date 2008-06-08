#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use HTTP::Request;
use LWP::UserAgent;
use Encode;

# 文書情報を取得したいID
# my $query = "ゴルフ"; # スニペット生成に必要
# my $dat = "<Docinfo result_items=\"Url:Cache:Snippet:Title\" query=\"$query\">\n";
# $dat .= "<Doc Id=\"072520902\" Rank=\"1\" />\n";
# $dat .= "<Doc Id=\"050282161\" Rank=\"2\" />\n";
# $dat .= "<Doc Id=\"066674292\" Rank=\"3\" />\n";
# $dat .= "<Doc Id=\"056418429\" Rank=\"4\" />\n";
# $dat .= "<Doc Id=\"031085086\" Rank=\"5\" />\n";
# $dat .= "</Docinfo>\n";



my $dat = qq(<DocInfo result_items="Id:Snippet" query="アガリクス茸で行こう" highlight="1">);
$dat .= qq(<Doc Id ="090069692" />);
$dat .= qq(<Doc Id ="027686751" />);
$dat .= qq(<Doc Id ="004726148" />);
$dat .= qq(<Doc Id ="092264760" />);
$dat .= qq(<Doc Id ="092264761" />);
$dat .= qq(<Doc Id ="013770115" />);
$dat .= qq(<Doc Id ="053231706" />);
$dat .= qq(<Doc Id ="064408202" />);
$dat .= qq(<Doc Id ="004726149" />);
$dat .= qq(<Doc Id ="027686750" />);
$dat .= qq(<Doc Id ="032856101" />);
$dat .= qq(<Doc Id ="086880690" />);
$dat .= qq(<Doc Id ="090069709" />);
$dat .= qq(<Doc Id ="017695111" />);
$dat .= qq(<Doc Id ="004726142" />);
$dat .= qq(<Doc Id ="090069706" />);
$dat .= qq(<Doc Id ="067742960" />);
$dat .= qq(<Doc Id ="092264762" />);
$dat .= qq(<Doc Id ="057443359" />);
$dat .= qq(<Doc Id ="026682805" />);
$dat .= qq(</DocInfo>);

# UserAgent の作成
my $ua = LWP::UserAgent->new;
my $url = "http://iccc004.crawl.kclab.jgn2.jp/~skeiji/cgi-bin/SearchEngine/cgi/api.cgi";
my $url = "http://www3.crawl.kclab.jgn2.jp/wisdom-lb/tsubaki/api.cgi";

my $req = HTTP::Request->new(POST => $url);
$req->content(encode('utf8', $dat));

# API に問い合わせ
$ua->credentials("iccc004.crawl.kclab.jgn2.jp:80", "Restricted Area", "3wisdoms", "!melchior!");
my $res = $ua->request($req);

# 結果を出力
print $res->as_string;
