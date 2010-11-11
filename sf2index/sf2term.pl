#!/usr/bin/env perl

# a script to convert standard format to term file

#$Id$

use strict;
use utf8;
use Getopt::Long;
use XML::LibXML;

our %opt;
&GetOptions(\%opt, 'suffix=s');

our $SF_EXT = 'xml';
our $IDX_EXT = $opt{suffix} ? $opt{suffix} : 'idx';
our $parser = new XML::LibXML;

for my $file (@ARGV) {
    my ($prefix, $doc_id) = ($file =~ /^(.*)(\d+)\.$SF_EXT$/);
    die "Please rename the input filename to hogehoge[0-9]+.$SF_EXT\n" unless defined($doc_id);
    my $output_file = $prefix . $doc_id . '.' . $IDX_EXT;

    my $xmldat;
    open(XML, '< :utf8', $file) or die;
    while (<XML>) {
	$xmldat .= $_;
    }
    close(XML);
    &xml2term($parser, $doc_id, $xmldat, $output_file);
}


sub xml2term {
    my ($parser, $doc_id, $xmldat, $output_file) = @_;

    my $doc = $parser->parse_string($xmldat);

    my (%terms, %dpnd_terms);
    my $word_count = 0;
    for my $sentence_node ($doc->getElementsByTagName('S')) {
	my $sentence_id = $sentence_node->getAttribute('id');
	my (%phrases);
	for my $result_node ($doc->getElementsByTagName('result')) {
	    for my $result_child_node ($result_node->getChildNodes) {
		next unless $result_child_node->nodeName eq 'phrase';
		my (@words);
		for my $phrase_child_node ($result_child_node->getChildNodes) {
		    next unless $phrase_child_node->nodeName eq 'word';
		    my $term = $phrase_child_node->getAttribute('midasi');
		    # word terms
		    $terms{$term}{freq}++;
		    $terms{$term}{sentence_ids}{$sentence_id}++;
		    $terms{$term}{pos}{$word_count} = 1; # value = score
		    push(@words, {str => $term,
				  feature => $phrase_child_node->getAttribute('feature'), 
				  pos => $word_count});
		    $word_count++;
		}
		my $id = $result_child_node->getAttribute('id');
		my $word_head_num = &get_phrase_head_num(\@words);
		$phrases{$id} = {head_ids => [split('/', $result_child_node->getAttribute('head'))], 
				 words => \@words, 
				 word_head_num => $word_head_num, # head word in this phrase
				 str => $words[$word_head_num]{str}, 
				 pos => $words[$word_head_num]{pos}, 
				};
	    }
	}

	# dpnd terms
	for my $id (sort {$phrases{$a} <=> $phrases{$b}} keys %phrases) {
	    next if !$phrases{$id}{head_ids}; # skip roots of English (undef)
	    for my $head_id (@{$phrases{$id}{head_ids}}) {
		next if $head_id == -1; # skip roots of Japanese (-1)
		my $dpnd_term = sprintf('%s->%s', $phrases{$id}{str}, $phrases{$head_id}{str});
		$dpnd_terms{$dpnd_term}{freq}++;
		$dpnd_terms{$dpnd_term}{sentence_ids}{$sentence_id}++;
		$dpnd_terms{$dpnd_term}{pos}{$phrases{$id}{pos}} = 1; # value = score
	    }
	}
    }

    # register word terms and dpnd terms
    open(OUT, '>:utf8', $output_file) or die;
    &register_terms($doc_id, \%terms, *OUT);
    &register_terms($doc_id, \%dpnd_terms, *OUT);
    close(OUT);
}

sub register_terms {
    my ($doc_id, $terms_hr, $OUTPUT) = @_;

    for my $term (keys %{$terms_hr}) {
	my @buf;
	for my $pos (sort keys %{$terms_hr->{$term}{pos}}) {
	    push @buf, sprintf "%s&%s", $pos, $terms_hr->{$term}{pos}{$pos};
	}

	printf $OUTPUT "%s %s:%.2f@%s#%s\n", $term, $doc_id, $terms_hr->{$term}{freq}, join (',', sort {$a <=> $b} keys %{$terms_hr->{$term}{sentence_ids}}), join ',', @buf;
    }
}

sub get_phrase_head_num {
    my ($words_ar) = @_;

    for my $i (0 .. $#{$words_ar}) {
	if ($words_ar->[$i]{feature} =~ /<自立>/) {
	    return $i;
	}
    }
    return -1;
}
