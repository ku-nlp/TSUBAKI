#!/usr/bin/env perl

# a script to convert standard format to term file

#$Id$

use strict;
use utf8;
use Getopt::Long;
use XML::LibXML;

binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');

my $doc_id = 100;
my $xmldat;
while (<STDIN>) {
    $xmldat .= $_;
}

my $parser = new XML::LibXML;
my $doc = $parser->parse_string($xmldat);

my %terms;
my $word_count = 0;
for my $sentence_node ($doc->getElementsByTagName('S')) {
    my $sentence_id = $sentence_node->getAttribute('id');
    for my $result_node ($doc->getElementsByTagName('result')) {
	for my $result_child_node ($result_node->getChildNodes) {
	    next unless $result_child_node->nodeName eq 'phrase';
	    for my $phrase_child_node ($result_child_node->getChildNodes) {
		next unless $phrase_child_node->nodeName eq 'word';
		$terms{$phrase_child_node->string_value}{freq}++;
		$terms{$phrase_child_node->string_value}{sentence_ids}{$sentence_id}++;
		$terms{$phrase_child_node->string_value}{pos}{$word_count} = 1; # score
		$word_count++;
	    }
	}
    }
}

for my $term (keys %terms) {
    my @buf;
    for my $pos (sort keys %{$terms{$term}{pos}}) {
	push @buf, sprintf "%s&%s", $pos, $terms{$term}{pos}{$pos};
    }

    printf "$term $doc_id:%.2f@%s#%s\n", $terms{$term}{freq}, join (',', sort {$a <=> $b} keys %{$terms{$term}{sentence_ids}}), join ',', @buf;
}
