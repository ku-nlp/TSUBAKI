#!/usr/bin/env perl

use strict;
use utf8;
use CDB_File;
use URI;
use URI::Split qw(uri_split uri_join);
use URI::Escape;


binmode (STDIN,  ':utf8');
binmode (STDOUT, ':utf8');
binmode (STDERR, ':encoding(euc-jp)');

&main;

sub main {
    tie my %url2did, 'CDB_File', $ARGV[0] or die "$!\n";
    tie my %did2url, 'CDB_File', $ARGV[1] or die "$!\n";

    while (<STDIN>) {
	chop;
	my ($did, $url, $anchor) = split (/\t+/, $_);
	next if ($anchor eq '');

	my $baseurl = $did2url{$did};
	if ($baseurl) {
	    my $URL = &convertURL($baseurl, $url);
	    my $DID = $url2did{$URL};
	    if ($DID) {
		printf "%s\t%s\t%s\t%s\t%s\n", $did, $baseurl, $DID, $URL, $anchor;
	    }
	} else {
	    printf STDERR "[WARNING] $_\n";
	}
    }

    untie %url2did;
    untie %did2url;
}

# 相対パスから絶対パスへ変換
sub convertURL {
    my ($url, $fpath) = @_;

    my $returl = (defined $url) ? URI->new($fpath)->abs($url) : $fpath;

    # 制御コードを削除
    $returl =~ tr/\x00-\x1f\x7f-\x9f//d;

    return $returl;
}
