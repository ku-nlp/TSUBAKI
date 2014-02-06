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
use Configure;


my $CONFIG;
# モジュールのパスを設定
BEGIN {
    $CONFIG = Configure::get_instance();
    push(@INC, $CONFIG->{TSUBAKI_MODULE_PATH});
}

use Tsubaki::CacheManager;

binmode (STDOUT, 'utf8');

print header(-charset => 'utf-8');

my $CGI = new CGI();
my $BASE_URL = $CONFIG->{WEBCLUSTERING_BASE_URL};
my $ORG_REFERER = $CGI->param('org_referer');
my $selected_cluster_id = -1 ; $selected_cluster_id = $1 if ($ORG_REFERER =~ /&cluster_id=(\d+)/);
$ORG_REFERER =~ s/&cluster_id=\d+//;
$ORG_REFERER =~ s/&cluster_label=([^&]+)//;
$ORG_REFERER =~ s/start=\d+/start=1/;
my $QUERY = &uri_escape($CGI->param('query'));
my $RAW_QUERY = $CGI->param('query'); $RAW_QUERY = decode ('utf8', $RAW_QUERY) unless (utf8::is_utf8($RAW_QUERY));
my $NUM_OF_PAGE = $CGI->param('num');
my $REMOVE_SYNIDS = $CGI->param('remove_synids');
my $TERM_STATES = $CGI->param('term_states');
my $DPND_STATES = $CGI->param('dpnd_states');

my $DOC_DATA = $CGI->param('dids');
my $REQUEST_URI = sprintf ("%s?query=%s&api=1&num=%d&organized_method=predicate_argument_with_grouping", $BASE_URL, $QUERY, $NUM_OF_PAGE);

&main();

sub main {

    my $key = sprintf ("clustering{query=%s,remove_synids=%s,term_states=%s,dpnd_states=%s}",
		       &uri_escape(encode('utf8', $QUERY)),
		       $REMOVE_SYNIDS,
		       $TERM_STATES,
		       $DPND_STATES);
    my $key = sprintf ("clustering{query=%s}", $QUERY);
    my $cache = new Tsubaki::CacheManager();
    my $xmldat = $cache->load($key);
    # cache のチェック
    unless ($xmldat) {
	$xmldat = &getClusteringResult();
	$xmldat = decode('utf-8', $xmldat);
	# ログの保存
	$cache->save($key, $xmldat, 'TXT');
    } else {
	sleep 1;
    }

    my $parser = new XML::LibXML;
    my $result = $parser->parse_string($xmldat);
    &printClusteringResult($result);
}

sub makeClusteringDocinfo {
    my $docinfo = sprintf (qq(<ClusteringDocinfo query="%s" organized_method="predicate_argument_with_grouping">\n), $RAW_QUERY);
    my $rank = 1;
    foreach my $did (split (",", $DOC_DATA)) {
	$docinfo .= sprintf (qq(\t<Doc Id="%s" Rank="%d"/>\n), $did, $rank++);
    }
    $docinfo .= "</ClusteringDocinfo>\n";

    return $docinfo;
}

sub getClusteringResult {
    # POST data 
    my $DOCINFO = &makeClusteringDocinfo();

    # UserAgent の作成
    my $ua = new LWP::UserAgent();

    # リクエストの送信
    my $req = HTTP::Request->new(POST => $REQUEST_URI);
    $req->content(encode('utf8', $DOCINFO));
    my $response = $ua->request($req);

    # APIの結果を取得
    if ($response->is_success()) {
	return $response->content();
    } else {
	return undef;
    }
}

sub printClusteringResult {
    my ($result) = @_;

    my %id2midasi = ();
    my %midasi2did = ();
    my %parent2children = ();
    my %contradiction = ();

    my @major_PA_cluster;
    foreach my $cluster ($result->getElementsByTagName('Cluster')) {
	my $id = $cluster->getAttribute('Id');
	my $midasi = $cluster->getAttribute('Label');
	my $parentId = $cluster->getAttribute('ParentId');
	my $contradictionId = $cluster->getAttribute('ContradictionId');

	$id2midasi{$id} = ((utf8::is_utf8($midasi)) ? $midasi : decode('utf8', $midasi));
	# major_PA_cluster
	if ($id >= 1000) {
	    if ($contradictionId) {
		push(@{$contradiction{$contradictionId}}, $id);
	    }
	    else {
		push @major_PA_cluster, { cid => $id, midasi => $midasi } if !$parentId;
	    }
	}
	elsif ($parentId) {
	    push(@{$parent2children{$parentId}}, $id);
	}

	foreach my $doc ($cluster->getElementsByTagName('Doc')) {
	    push (@{$midasi2did{$midasi}}, $doc->getAttribute('Id'));
	}
    }

    print qq(<DIV style="padding: 0em; border: 0px solid gray;">);
    if ($selected_cluster_id > -1) {
	print qq(<DIV class='clustering_off'><A href="$ORG_REFERER">絞り込みを解除</A></DIV>\n);
    } else {
	print qq(<DIV  class='clustering_off' style="color: gray;">絞り込みを解除</DIV>\n);
    }

    print qq(<DIV style="border-bottom: 1px solid black; border-left: 1em solid brown; margin-bottom:1em;">　<font color=brown>関連語</font></DIV>\n);
    foreach my $pid (sort {$a <=> $b} keys %parent2children) {
	print qq(<DIV style="border-bottom: 1px solid black; border-left: 1em solid black;  margin-left:0.5em;">　$id2midasi{$pid}</DIV>\n);
	print qq(<DIV style="padding: 0.3em 0em 1em 0.5em;">);
	foreach my $cid (sort {$a <=> $b} @{$parent2children{$pid}}) {
	    my $midasi = $id2midasi{$cid};
	    &print_anchor_text($ORG_REFERER, $cid, $midasi);
	}
	print qq(</DIV>);
    }

    if (scalar @major_PA_cluster) {
	print qq(<hr style="margin-bottom:1em;">);
	print qq(<DIV style="border-bottom: 1px solid black; border-left: 1em solid brown;">　<font color=brown>主要・対立表現</font></DIV>\n);
	print qq(<DIV style="padding: 0.3em 0em 1em 0.5em;">);
	for my $major_PA (@major_PA_cluster) {
	    my $cid = $major_PA->{cid};
	    my $midasi = $id2midasi{$cid};
	    &print_anchor_text($ORG_REFERER, $cid, $midasi);
	    if (defined $contradiction{$cid}) {
		for my $contradict_id (@{$contradiction{$cid}}) {
		    my $c_midasi = $id2midasi{$contradict_id};
		    print qq( <br>&nbsp;&nbsp;⇔ ); &print_anchor_text($ORG_REFERER, $contradict_id, $c_midasi);
		}
	    }
	    print qq(<br>);
	}
	print qq(</DIV>);
    }
    print qq(</DIV>);

}

sub print_anchor_text {
    my ($ORG_REFERER, $cid, $midasi) = @_;

    my $url = sprintf ("%s&cluster_id=%s&cluster_label=%s", $ORG_REFERER, $cid, &uri_escape(encode('utf8', $midasi)));
    if ($cid == $selected_cluster_id) {
	print "<SPAN class='clustering_label'>" . $midasi . "</SPAN>\n";
    } else {
	print "<A class='clustering_label' href='$url'>" . $midasi . "</A>\n";
    }
}
