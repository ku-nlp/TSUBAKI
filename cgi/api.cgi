#!/share/usr/bin/perl

# REST API for search

# Request parameters
# query   : utf8 encoded query
# results : the number of search results
# start   : start position of search results

# Output response (XML)
# ResultSet : a set of results, this field has the following attributes
#   totalResultsAvailable : the number of all results
#   totalResultsReturned  : the number of returned results
#   firstResultPosition   : start position of search results
# Result    : a result

use strict;
use Retrieve;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use XML::Writer;
use XML::DOM;
use File::stat;
use POSIX qw(strftime);
use Encode;
use URI::Escape qw(uri_escape);

my $CACHE_PROGRAM = 'http://reed.kuee.kyoto-u.ac.jp/SearchEngine/index.cgi';
my $HTML_PATH_TEMPLATE = 'INDEX/%02d/h%04d/%08d.html';
my $SF_PATH_TEMPLATE   = 'INDEX/%02d/x%04d/%08d.xml';

my $retrieve = new Retrieve('INDEX'); # give the index dir
my $cgi = new CGI;

# utf8 encoded query
my $query = decode('utf8', $cgi->param('query'));
my $uri_escaped_query = uri_escape(encode('euc-jp', $query)); # uri_escape_utf8($query);

# number of search results
my $result_num = $cgi->param('results');
$result_num = 10 unless $result_num; # default number of results

# start position of results
my $start_num = $cgi->param('start');
$start_num = 1 unless $start_num;

# current time
my $timestamp = strftime("%Y-%m-%d %T", localtime(time));

# print HTTP header
print $cgi->header(-type => 'text/xml', 
		   -charset => 'utf-8', 
		  );

# prepare XML output
my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
$writer->xmlDecl('utf-8');

# XML DOM Parser for acquiring information of HTML
my $parser = new XML::DOM::Parser;

# search
my @result = $retrieve->search($query);
my @ret_result = &get_results_specified_num(\@result, $start_num, $result_num);

$writer->startTag('ResultSet', time => $timestamp, query => $query, 
		  totalResultsAvailable => scalar(@result), 
		  totalResultsReturned => scalar(@ret_result), 
		  firstResultPosition => $start_num);

for my $d (@ret_result) {
    $writer->startTag('Result', Id => sprintf("%08d", $d->{did}), Score => sprintf("%.5f", $d->{score}));

#    $writer->startTag('Title');
#    $writer->characters(&get_file_info($d->{did}));
#    $writer->endTag('Title');

    $writer->startTag('Cache');
    $writer->startTag('Url');
    $writer->characters(&get_cache_location($d->{did}, $uri_escaped_query));
    $writer->endTag('Url');
    $writer->startTag('Size');
    $writer->characters(&get_cache_size($d->{did}));
    $writer->endTag('Size');
    $writer->endTag('Cache');

    $writer->endTag('Result');
}

$writer->endTag('ResultSet');
$writer->end();


sub get_results_specified_num {
    my ($result, $start, $num) = @_;
    my (@ret);

    $start--; # index starts from 0
    for my $i ($start .. $start + $num - 1) {
	last if $i >= scalar(@$result);
	push(@ret, $result->[$i]);
    }

    return @ret;
}

sub get_cache_location {
    my ($id, $query) = @_;

    my $loc = sprintf($HTML_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id);
#    return "${CACHE_PROGRAM}?loc=$loc&query=$uri_escaped_query";
    return "${CACHE_PROGRAM}?URL=$loc&KEYS=$uri_escaped_query";
}

sub get_cache_size {
    my ($id) = @_;

    my $st = stat(sprintf($HTML_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id));
    return '' unless $st;
    return $st->size;
}

sub get_file_info {
    my ($id) = @_;

    my $filename = sprintf($SF_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id);
    return '' unless -f $filename;
    my $doc = $parser->parsefile($filename);

    my $sentences = $doc->getElementsByTagName('S');
    for my $i (0 .. $sentences->getLength - 1) { # for each S
	my $sentence = $sentences->item($i);
	for my $s_child_node ($sentence->getChildNodes) {
	    if ($s_child_node->getNodeName eq 'RawString') { # one of the children of S is RawString
		for my $node ($s_child_node->getChildNodes) {
		    $doc->dispose;
		    return $node->getNodeValue; # the first one is title
		}
	    }
	}
    }

    $doc->dispose;
    return '';
}
