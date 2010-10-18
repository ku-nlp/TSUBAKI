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
		my $term = $phrase_child_node->string_value;
		# word terms
		$terms{$term}{freq}++;
		$terms{$term}{sentence_ids}{$sentence_id}++;
		$terms{$term}{pos}{$word_count} = 1; # value = score
		push(@words, {str => $phrase_child_node->string_value, 
			      feature => $phrase_child_node->getAttribute('feature'), 
			      pos => $word_count});
		$word_count++;
	    }
	    my $id = $result_child_node->getAttribute('id');
	    my $word_head_num = &get_phrase_head_num(\@words);
	    $phrases{$id} = {head_id => $result_child_node->getAttribute('head'), 
			     words => \@words, 
			     word_head_num => $word_head_num, # head word in this phrase
			     str => $words[$word_head_num]{str}, 
			     pos => $words[$word_head_num]{pos}, 
			    };
	}
    }

    # dpnd terms
    for my $id (sort {$phrases{$a} <=> $phrases{$b}} keys %phrases) {
	next if $phrases{$id}{head_id} == -1; # skip roots
	my $dpnd_term = sprintf('%s->%s', $phrases{$id}{str}, $phrases{$phrases{$id}{head_id}}{str});
	$dpnd_terms{$dpnd_term}{freq}++;
	$dpnd_terms{$dpnd_term}{sentence_ids}{$sentence_id}++;
	$dpnd_terms{$dpnd_term}{pos}{$phrases{$id}{pos}} = 1; # value = score
    }
}

# register word terms and dpnd terms
&register_terms(\%terms);
&register_terms(\%dpnd_terms);


sub register_terms {
    my ($terms_hr) = @_;

    for my $term (keys %{$terms_hr}) {
	my @buf;
	for my $pos (sort keys %{$terms_hr->{$term}{pos}}) {
	    push @buf, sprintf "%s&%s", $pos, $terms_hr->{$term}{pos}{$pos};
	}

	printf "$term $doc_id:%.2f@%s#%s\n", $terms_hr->{$term}{freq}, join (',', sort {$a <=> $b} keys %{$terms_hr->{$term}{sentence_ids}}), join ',', @buf;
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
