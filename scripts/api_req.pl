#!/usr/bin/env perl

# TSUBAKI APIに問い合わせて、検索結果、標準フォーマットを取得するスクリプト

# $Id$

use LWP::UserAgent;
use URI::Escape;
use Encode;
use Encode::Guess;
use utf8;
use Getopt::Long;
use strict;

my (%opt);
GetOptions(\%opt, 'query=s', 'start=i', 'results=i', 'download=s', 'proxy', 'proxy_server=s', 'format=s', 'verbose', 'getdoc', 'base_url=s', 'snippet', 'title', 'did=s');

$opt{base_url} = 'http://tsubaki.ixnlp.nii.ac.jp/api.cgi' unless ($opt{base_url});
$opt{proxy_server} = 'http://proxy.kuins.net:8080' if ($opt{proxy} && !$opt{proxy_server});
$opt{format} = 'xml' unless ($opt{format});

if ($opt{getdoc}) {
    &main4getdoc();
} else {
    &main();
}

sub main4getdoc {
	if ($opt{did}) {
		print &getxml($opt{did});
	}
	else {
		while (<STDIN>) {
			chop;

			my $did = $_;
			my $xmldat = &getxml($did);
			open (F, "> $did.xml") or die $!;
			print F $xmldat;
			close (F);
		}
	}
}


sub main {
    # 検索したいキーワード (utf8)をURIエンコードする
    my $uri_escaped_query = uri_escape($opt{query});

    # リクエストURLを作成
    my $results = (defined $opt{results}) ? $opt{results} : 10;
    my $start = (defined $opt{start}) ? $opt{start} : 1;
	my $result_items = 'Id';
	$result_items .= ':Snippet' if ($opt{snippet});
	$result_items .= ':Title' if ($opt{title});
    my $req_url = "$opt{base_url}?query=$uri_escaped_query&results=$results&start=$start";
    $req_url .= "&logical_operator=AND&dpnd=1&force_dpnd=0&no_snippets=1&result_items=$result_items";

    print STDERR $req_url . "\n" if ($opt{verbose});

    # UserAgent の作成
    my $ua = new LWP::UserAgent();
    # Proxy の設定
    $ua->proxy('http', $opt{proxy_server}) if ($opt{proxy});
    # タイムアウトの設定
    $ua->timeout(3600);

    # リクエストの送信
    my $req = HTTP::Request->new(GET => $req_url);
    $req->header('Accept' => 'text/xml');
    my $response = $ua->request($req);

    # TSUBAKI APIの結果を取得
    my $xmldat;
    if ($response->is_success()) {
	$xmldat = $response->content();

	unless ($opt{download}) {
	    print $xmldat;
	} else {
	    mkdir($opt{download}) unless (-e $opt{download});

	    open(WRITER, sprintf("> %s/result.xml", $opt{download})) or die;
	    print WRITER $xmldat;
	    close(WRITER);
	}

	print STDERR "Succeeded in getting search results.\n" if ($opt{verbose});
    } else {
	print STDERR "Failed to call the TSUBAKI API.\n";
    }

    if ($xmldat && $opt{download}) {
	while ($xmldat =~ /<Result Rank="(\d+)" Id="(\d+)">/g) {
	    my $rank = $1;
	    my $did = $2;

	    my $requestURL = "$opt{base_url}?id=$did&format=$opt{format}";

	    # リクエストの送信
	    my $req = HTTP::Request->new(GET => $requestURL);
	    $req->header('Accept' => 'text/xml');
	    my $response = $ua->request($req);

	    if ($response->is_success()) {
		open(WRITER, sprintf("> %s/%04d.$opt{format}", $opt{download}, $rank)) or die;
		print WRITER $response->content();
		close(WRITER);

		print STDERR "Succeeded in getting the standard format file (Rank=$rank, Id=$did).\n" if ($opt{verbose});
	    } else {
		print STDERR "Failed to call the TSUBAKI API.\n";
	    }
	}
    }
}

sub getxml {
	my ($did) = @_;

    # リクエストURLを作成
    my $req_url = "$opt{base_url}?format=xml";

	my $_req_url = sprintf ("%s&id=%s", $req_url, $did);

	# UserAgent の作成
	my $ua = new LWP::UserAgent();

	# リクエストの送信
	my $req = HTTP::Request->new(GET => $_req_url);
	$req->header('Accept' => 'text/xml');
	my $response = $ua->request($req);

	# TSUBAKI APIの結果を取得
	my $xmldat;
	if ($response->is_success()) {
		$xmldat = $response->content();
		return $xmldat;
	}
}
