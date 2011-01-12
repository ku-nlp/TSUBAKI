#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use LWP::UserAgent;
use URI::Escape;
use XML::LibXML;

# binmode (STDOUT, ':utf8');
print header(-charset => 'utf-8');

my $CGI = new CGI();

my $BASE_URL = 'http://nlpc06.ixnlp.nii.ac.jp/cgi-bin/shibata/WebClustering/api.cgi';
if ($CGI->param('query')) {
    my $QUERY = uri_escape($CGI->param('query'));
    my $NUM_OF_PAGE = $CGI->param('num');
    my $REQUEST_URI = sprintf ("%s?query=%s&api=1&num=%d&organized_method=grouping", $BASE_URL, $QUERY, $NUM_OF_PAGE);

    # UserAgent の作成
    my $ua = new LWP::UserAgent();

    # リクエストの送信
    my $req = HTTP::Request->new(GET => $REQUEST_URI);
    $req->header('Accept' => 'text/xml');
    my $response = $ua->request($req);

    # TSUBAKI APIの結果を取得
    if ($response->is_success()) {
	my $xmldat = $response->content();
	my $parser = new XML::LibXML;
	my $doc = $parser->parse_string($xmldat);
	my %id2midasi = ();
	my %parent2children = ();
	foreach my $cluster ($doc->getElementsByTagName('Cluster')) {
	    my $id = $cluster->getAttribute('Id');
	    my $midasi = $cluster->getAttribute('Label');
	    my $parentId = $cluster->getAttribute('ParentId');
	    $id2midasi{$id} = $midasi;
	    if ($parentId) {
		push(@{$parent2children{$parentId}}, $id);
	    }
	}

	print qq(<DIV style="padding: 0em; border: 0px solid gray;">);
	foreach my $pid (sort {$a <=> $b} keys %parent2children) {
	    print qq(<DIV style="border-bottom: 1px solid black; border-left: 1em solid black;">　$id2midasi{$pid}</DIV>\n);
	    print qq(<DIV style="padding: 0.3em 0em 1em 0.5em;">);
	    foreach my $cid (sort {$a <=> $b} @{$parent2children{$pid}}) {
		print "<SPAN style='padding: 0em 1em 0em 0em;'>" . $id2midasi{$cid} . "</SPAN>\n";
	    }
	    print qq(</DIV>);
	}
	print qq(</DIV>);
    }
}
