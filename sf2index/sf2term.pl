#!/usr/bin/env perl

# a script to convert standard format to term file

# $Id$

use strict;
use utf8;
use Getopt::Long;
use XML::LibXML;

our %opt;
&GetOptions(\%opt, 'suffix=s');

our $SF_EXT = 'xml';
our $IDX_EXT = $opt{suffix} ? $opt{suffix} : 'idx';
our $parser = new XML::LibXML;

my $file = $ARGV[0];
my ($prefix, $doc_id) = ($file =~ /^(.*?)([-\d]+)\.$SF_EXT$/);
die "Please rename the input filename to hogehoge[0-9]+.$SF_EXT\n" unless defined($doc_id);
my $output_file = $prefix . $doc_id . '.' . $IDX_EXT;

my $xmldat;
open(XML, '< :utf8', $file) or die;
while (<XML>) {
    $xmldat .= $_;
}
close(XML);
&xml2term($parser, $doc_id, $xmldat, $output_file);

sub xml2term {
    my ($parser, $doc_id, $xmldat, $output_file) = @_;

    my $doc = $parser->parse_string($xmldat);

    my (%terms, %dpnd_terms);
    my $word_count = 0;
    for my $sentence_node ($doc->getElementsByTagName('S')) { # sentence loop
	my $sentence_id = $sentence_node->getAttribute('id');
	my (%phrases);
	for my $annotation_node ($sentence_node->getElementsByTagName('Annotation')) { # parse
	    for my $phrase_node ($annotation_node->getElementsByTagName('phrase')) {
		my (@words);
		for my $word_node ($phrase_node->getElementsByTagName('word')) {
		    my $str = $word_node->getAttribute('str'); # word terms (string that appeared)
		    $str .= '*' if $str;
		    my $lem = $word_node->getAttribute('lem'); # word terms (lem)
		    for my $term ($str, $lem) {
			next unless $term;
			&hash_term(\%terms, $term, $sentence_id, $word_count, 1); # score=1
		    }
		    push(@words, {str => $str, lem => $lem, 
				  feature => $word_node->getAttribute('feature'), 
				  pos => $word_count});
		    $word_count++;

		    for my $synnode ($word_node->getElementsByTagName('synnode')) { # synonym node
			my $synid = $synnode->getAttribute('synid');
			my $score = $synnode->getAttribute('score');
			next unless $score < 1; # except the identical expression with the word
			my $wordid = (split(',', $synnode->getAttribute('wordid')))[0]; # the first wordid
			&hash_term(\%terms, $synid, $sentence_id, $wordid, $score);
		    }
		}
		my $id = $phrase_node->getAttribute('id');
		my $word_head_num = &get_phrase_head_num(\@words);
		$phrases{$id} = {head_ids => [split('/', $phrase_node->getAttribute('head'))], 
				 words => \@words, 
				 word_head_num => $word_head_num, # head word in this phrase
				 str => $words[$word_head_num]{str}, 
				 lem => $words[$word_head_num]{lem}, 
				 pos => $words[$word_head_num]{pos}, 
				};
	    }
	}

	# dpnd terms
	for my $id (sort {$phrases{$a} <=> $phrases{$b}} keys %phrases) {
	    next if !$phrases{$id}{head_ids}; # skip roots of English (undef)
	    for my $head_id (@{$phrases{$id}{head_ids}}) {
		next if $head_id == -1; # skip roots of Japanese (-1)
		my $dpnd_str = sprintf('%s->%s', $phrases{$id}{str}, $phrases{$head_id}{str}); # string that appeared
		my $dpnd_lem = sprintf('%s->%s', $phrases{$id}{lem}, $phrases{$head_id}{lem}); # lem
		for my $dpnd_term ($dpnd_str, $dpnd_lem) {
		    next if $dpnd_term eq '->';
		    &hash_term(\%dpnd_terms, $dpnd_term, $sentence_id, $phrases{$id}{pos}, 1); # score=1
		}
	    }
	}
    }

    # register word terms and dpnd terms
    open(OUT, '>:utf8', $output_file) or die;
    &register_terms($doc_id, \%terms, *OUT);
    &register_terms($doc_id, \%dpnd_terms, *OUT);
    close(OUT);
}

sub hash_term {
    my ($terms_hr, $term, $sentence_id, $word_count, $score) = @_;

    $terms_hr->{$term}{score} += $score;
    $terms_hr->{$term}{sentence_ids}{$sentence_id}++;
    $terms_hr->{$term}{pos}{$word_count} = $score;
}

sub register_terms {
    my ($doc_id, $terms_hr, $OUTPUT) = @_;

    for my $term (keys %{$terms_hr}) {
	my @buf;
	for my $pos (sort keys %{$terms_hr->{$term}{pos}}) {
	    push @buf, sprintf "%s&%s", $pos, $terms_hr->{$term}{pos}{$pos};
	}

	printf $OUTPUT "%s %s:%.2f@%s#%s\n", $term, $doc_id, $terms_hr->{$term}{score}, join (',', sort {$a <=> $b} keys %{$terms_hr->{$term}{sentence_ids}}), join ',', @buf;
    }
}

sub get_phrase_head_num {
    my ($words_ar) = @_;

    for my $i (0 .. $#{$words_ar}) {
	if ($words_ar->[$i]{feature} =~ /<(?:準)?内容語>/) {
	    return $i;
	}
    }
    return -1;
}
