#!/usr/bin/env perl

use strict;
use LWP::Simple;
use XML::Simple;
use URI::Escape;
use Encode qw(from_to);

sub usage {
    print "$0 query (in euc-jp)\n";
    exit 1;
}

&usage() unless $ARGV[0];
my $query = $ARGV[0];
from_to($query, 'euc-jp', 'utf-8');
my $uri_escaped_query = uri_escape($query);

my $base_url = 'http://tsubaki.ixnlp.nii.ac.jp/api.cgi';
my $results = 20;
my $req_url = "$base_url?query=$uri_escaped_query&start=1&results=$results";

# Get Response from API
my $response = get($req_url);

# Parse the acquired XML
my $xml_mod = XML::Simple->new();
my $xml = $xml_mod->XMLin($response, ForceArray=>['Result']);

# the number of results
my $totalresults = $xml->{totalResultsAvailable};
print "Total results: $totalresults\n---\n";

# each result
my $count = 1;
for my $result (@{$xml->{Result}}) {
    my $cache_url = $result->{Cache}{Url};
    print "$count $cache_url\n";
    $count++;
}
