#!/usr/bin/env perl

# a script to convert standard format to term file

# $Id$

use strict;
use utf8;
use Getopt::Long;
use XML::LibXML;
use StandardFormat;

our %opt;
&GetOptions(\%opt, 'suffix=s');

our $SF_EXT = 'xml';
our $IDX_EXT = $opt{suffix} ? $opt{suffix} : 'idx';
our $parser = new XML::LibXML;
our $sf = new StandardFormat;

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
    for my $sentence_node ($doc->getElementsByTagName('S')) { # sentence loop
	my $sentence_id = $sentence_node->getAttribute('id');
	for my $annotation_node ($sentence_node->getElementsByTagName('Annotation')) { # parse
	    $sf->read_annotation_from_node($annotation_node);

	    for my $id (sort {$sf->{words}{$a}{pos} <=> $sf->{words}{$b}{pos}} keys %{$sf->{words}}) { # order: left-to-right
		my $word = $sf->{words}{$id};
		for my $term ($word->{str}, $word->{lem}) {
		    next unless $term;
		    &hash_term(\%terms, $term, $sentence_id, $word->{pos}, 1); # score=1
		}
		for my $synnode (@{$word->{synnodes}}) { # synonym node
		    next unless $synnode->{score} < 1; # except the identical expression with the word
		    my $wordid = (split(',', $synnode->{wordid}))[0]; # the first wordid
		    &hash_term(\%terms, $synnode->{synid}, $sentence_id, $wordid, $synnode->{score});
		}
	    }

	    for my $id (sort {$sf->{phrases}{$a} <=> $sf->{phrases}{$b}} keys %{$sf->{phrases}}) {
		next if !$sf->{phrases}{$id}{head_ids}; # skip roots of English (undef)
		for my $head_id (@{$sf->{phrases}{$id}{head_ids}}) {
		    next if $head_id == -1; # skip roots of Japanese (-1)
		    my $dpnd_str = sprintf('%s->%s', $sf->{phrases}{$id}{str}, $sf->{phrases}{$head_id}{str}); # string that appeared
		    my $dpnd_lem = sprintf('%s->%s', $sf->{phrases}{$id}{lem}, $sf->{phrases}{$head_id}{lem}); # lem
		    for my $dpnd_term ($dpnd_str, $dpnd_lem) {
			next if $dpnd_term eq '->';
			&hash_term(\%dpnd_terms, $dpnd_term, $sentence_id, $sf->{phrases}{$id}{pos}, 1); # score=1
		    }
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
