#!/usr/bin/env perl

# a script to convert standard format to term file

# $Id$

use strict;
use utf8;
use Getopt::Long;
use XML::LibXML;
use StandardFormat;

binmode(STDOUT, ':utf8');

our %opt;
&GetOptions(\%opt, 'suffix=s', 'autoout', 'no-repname', 'ignore_yomi', 'feature', 'blocktype=s', 'no_check_filename');
# if you specify 'no-repname', you must set IGNORE_YOMI to 1 in "conf/configure"

our %BLOCKTYPE2FEATURE;
if ($opt{blocktype}) {
    $opt{feature} = 1;
    # read feature bits for blocktypes
    open (F, '<:utf8', $opt{blocktype}) or die "$!\n";
    while (<F>) {
	next if /^\#/;
	chomp;
	my @data = split (/ /, $_);
	$BLOCKTYPE2FEATURE{$data[0]} = $data[5];
    }
    close (F);
}

our $SF_EXT = 'xml';
our $IDX_EXT = $opt{suffix} ? $opt{suffix} : 'idx';
our $parser = new XML::LibXML;
our $sf = new StandardFormat;

my $file = $ARGV[0];
my ($prefix, $doc_id) = ($file =~ /^(.*?)([-\d]+)\.$SF_EXT$/);
die "Please rename the input filename to hogehoge[0-9]+.$SF_EXT\n" if !$opt{no_check_filename} && !defined($doc_id);
my $output_file = $prefix . $doc_id . '.' . $IDX_EXT;

my $xmldat;
open(XML, '< :utf8', $file) or die "Cannot open an input XML: $file\n";
while (<XML>) {
    $xmldat .= $_;
}
close(XML);
&xml2term($parser, $doc_id, $xmldat, $output_file);

sub xml2term {
    my ($parser, $doc_id, $xmldat, $output_file) = @_;
    my (%terms, %dpnd_terms);

    if ($xmldat) { # if xml has content
	my $doc = $parser->parse_string($xmldat);

	for my $title_node ($doc->getElementsByTagName('Title')) { # title node
	    &process_one_sentence($title_node, 0, 'title', \%terms, \%dpnd_terms);
	}

	for my $sentence_node ($doc->getElementsByTagName('S')) { # sentence loop
	    my $sentence_id = $sentence_node->getAttribute('Id');
	    my $blocktype = $sentence_node->getAttribute('BlockType');
	    &process_one_sentence($sentence_node, $sentence_id, $blocktype, \%terms, \%dpnd_terms);
	}
    }

    # register word terms and dpnd terms
    if ($opt{autoout}) {
	open(OUT, '>:utf8', $output_file) or die;
    }
    else {
	*OUT = *STDOUT;
    }
    &register_terms($doc_id, \%terms, *OUT);
    &register_terms($doc_id, \%dpnd_terms, *OUT);
    close(OUT) if $opt{autoout};
}

sub process_one_sentence {
    my ($sentence_node, $sentence_id, $blocktype, $terms_hr, $dpnd_terms_hr) = @_;

    for my $annotation_node ($sentence_node->getElementsByTagName('Annotation')) { # parse
	$sf->read_annotation_from_node($annotation_node);

	for my $id (sort {$sf->{words}{$a}{position} <=> $sf->{words}{$b}{position}} keys %{$sf->{words}}) { # order: left-to-right
	    my $word = $sf->{words}{$id};
	    my (@terms);
	    push(@terms, $word->{str}); # string that appeared (string*)
	    if (!$opt{'no-repname'} && $word->{repname}) { # if repname exists, use this
		push(@terms, $opt{ignore_yomi} ? &remove_yomi($word->{repname}) : $word->{repname});
	    }
	    else {			# otherwise str and lem
		push(@terms, $word->{lem});
	    }
	    for my $term (@terms) {
		next unless $term;
		&hash_term($terms_hr, $term, $sentence_id, $word->{position}, 1, &create_feature($blocktype)); # score=1
	    }
	    for my $synnode (@{$word->{synnodes}}) { # synonym node
		next unless $synnode->{score} < 1; # except the identical expression with the word
		my $wordid = (split(',', $synnode->{wordid}))[0]; # the first wordid
		&hash_term($terms_hr, $synnode->{synid}, $sentence_id, $sf->{words}{$wordid}{position}, $synnode->{score}, &create_feature($blocktype));
	    }
	}

	# dependency
	for my $id (sort {$sf->{phrases}{$a} <=> $sf->{phrases}{$b}} keys %{$sf->{phrases}}) {
	    next if !$sf->{phrases}{$id}{head_ids}; # skip roots of English (undef)
	    for my $head_id (@{$sf->{phrases}{$id}{head_ids}}) {
		next if $head_id eq 'c-1'; # skip roots of Japanese (-1)
		my (@terms);
		push(@terms, sprintf('%s->%s', $sf->{phrases}{$id}{str}, $sf->{phrases}{$head_id}{str})); # string that appeared (aa*->bb*)
		if (!$opt{'no-repname'} && $sf->{phrases}{$id}{repname} && $sf->{phrases}{$head_id}{repname}) { # if repname exists, use this
		    push(@terms, sprintf('%s->%s', 
					 $opt{ignore_yomi} ? &remove_yomi($sf->{phrases}{$id}{repname}) : $sf->{phrases}{$id}{repname}, 
					 $opt{ignore_yomi} ? &remove_yomi($sf->{phrases}{$head_id}{repname}) : $sf->{phrases}{$head_id}{repname}));
		}
		else {			# lem->lem
		    push(@terms, sprintf('%s->%s', $sf->{phrases}{$id}{lem}, $sf->{phrases}{$head_id}{lem}));
		}
		for my $dpnd_term (@terms) {
		    next if $dpnd_term eq '->';
		    &hash_term($dpnd_terms_hr, $dpnd_term, $sentence_id, $sf->{phrases}{$id}{position}, 1, &create_feature($blocktype)); # score=1
		}
	    }
	}
    }
}

sub hash_term {
    my ($terms_hr, $term, $sentence_id, $word_count, $score, $feature) = @_;

    $terms_hr->{$term}{score} += $score;
    $terms_hr->{$term}{sentence_ids}{$sentence_id}++;
    $terms_hr->{$term}{position}{$word_count} = {score => $score, feature => $feature};
}

sub register_terms {
    my ($doc_id, $terms_hr, $OUTPUT) = @_;

    for my $term (keys %{$terms_hr}) {
	my @buf;
	for my $position (sort {$a <=> $b} keys %{$terms_hr->{$term}{position}}) {
	    my $str = sprintf "%s&%s", $position, $terms_hr->{$term}{position}{$position}{score};
	    if ($opt{feature}) { # when use features
		$str .= '&' . $terms_hr->{$term}{position}{$position}{feature};
	    }
	    push(@buf, $str);
	}

	printf $OUTPUT "%s %s:%.2f@%s#%s\n", $term, $doc_id, $terms_hr->{$term}{score}, join(',', sort {$a <=> $b} keys %{$terms_hr->{$term}{sentence_ids}}), join(',', @buf);
    }
}

sub remove_yomi {
    my ($text) = @_;

    my @buf;
    foreach my $word (split /\+/, $text) {
	if ($word =~ /^s\d+/) { # use synnode as it is
	    push(@buf, $word);
	}
	else {
	    my ($hyouki, $yomi) = split (/\//, $word);
	    push(@buf, $hyouki);
	}
    }

    return join('+', @buf)
}

sub create_feature {
    my ($blocktype) = @_;

    my $feature = 0;
    if ($blocktype && exists($BLOCKTYPE2FEATURE{$blocktype})) {
	$feature += $BLOCKTYPE2FEATURE{$blocktype};
    }

    return $feature;
}
