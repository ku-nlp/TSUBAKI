package StandardFormat;

# $Id$

# Read (new) standard format

use strict;
use XML::LibXML;
use utf8;

sub new {
    my ($this) = @_;

    $this = {parser => new XML::LibXML, word_count => 0};
    bless $this;
}


# read first annotation
sub read_first_annotation {
    my ($this, $xmldat) = @_;

    $this->{doc} = $this->{parser}->parse_string($xmldat);

    for my $annotation_node ($this->{doc}->getElementsByTagName('S')) { # parse
	$this->read_annotation_from_node($annotation_node);
	return;
    }
}

# read annotation from a given annotation node
sub read_annotation_from_node {
    my ($this, $annotation_node) = @_;

    undef $this->{words};
    undef $this->{phrases};

    for my $phrase_node ($annotation_node->getElementsByTagName('Chunk')) {
	my (@words);
	my $skip_chunk_flag = 0;
	for my $word_node ($phrase_node->getElementsByTagName('Token')) {
	    my $str = $word_node->getAttribute('surf'); # string that appeared
	    $skip_chunk_flag = 1 if $str =~ /\p{Specials}/; # mojibake
	}

	for my $word_node ($phrase_node->getElementsByTagName('Token')) {
	    my $str = $word_node->getAttribute('surf'); # string that appeared
	    $str .= '*' if $str;
	    my $lem = $word_node->getAttribute('orig'); # lemma
	    my $repname = $word_node->getAttribute('repname'); # repname
	    my $id = $word_node->getAttribute('id');
	    $this->{words}{$id} = {id => $id, 
				   str => $str, lem => $lem, repname => $repname, 
				   synnodes => [], 
				   pos => $word_node->getAttribute('pos1'), 
				   feature => $word_node->getAttribute('feature'), 
				   content_p => $word_node->getAttribute('content_p'), 
				   position => $this->{word_count}} if (!$skip_chunk_flag);

	    # predicate-argument structure
	    my @predicate_node = $word_node->getElementsByTagName('Predicate');
	    if (@predicate_node) {
		$this->{words}{$id}{arguments} = {};
		for my $attr_node ($predicate_node[0]->attributes()) { # e.g., ga="t21"
		    $this->{words}{$id}{arguments}{$attr_node->getValue()} = $attr_node->getName(); # id => case
		}
	    }

	    push(@words, $this->{words}{$id}) if (!$skip_chunk_flag);
	    $this->{word_count}++;

	    for my $synnode ($word_node->getElementsByTagName('synnode')) { # synonym node
		my $synid = $synnode->getAttribute('synid');
		my $score = $synnode->getAttribute('score');
		next unless $score < 1; # except the identical expression with the word
		my $wordid = (split(',', $synnode->getAttribute('wordid')))[0]; # the first wordid
		push(@{$this->{words}{$id}{synnodes}}, {synid => $synid, score => $score, wordid => $wordid}) if (!$skip_chunk_flag);
	    }
	}
	my $id = $phrase_node->getAttribute('id');
	my $word_head_num = &get_phrase_head_num(\@words);
	$this->{phrases}{$id} = {id => $id, 
				 head_ids => [split('/', $phrase_node->getAttribute('head'))], 
				 words => \@words, 
				 word_head_num => $word_head_num, # head word in this phrase
				 word_head_id => $words[$word_head_num]{id}, # the id of head word in this phrase
				 str => $words[$word_head_num]{str}, 
				 lem => $words[$word_head_num]{lem}, 
				 repname => $words[$word_head_num]{repname}, 
				 position => $words[$word_head_num]{position}, 
	} if (!$skip_chunk_flag);
    }
}

sub get_knp_objects {
    my ($this, $xmldat) = @_;

    my $doc = $this->{parser}->parse_string($xmldat);

    my @knp_objects;
    for my $annotation_node ($doc->getElementsByTagName('Annotation')) { # parse
	my $knp_string = $this->convert_knp_format($annotation_node);
	next if $knp_string eq "EOS\n";
	push @knp_objects, new KNP::Result($knp_string);
    }

    return \@knp_objects;
}

sub convert_knp_format {
    my ($this, $annotation_node) = @_;

    my $knp_format_string;

    my %parent_tid;
    my %bnst_span;
    my $current_bnst_id = -1;
    my %tid2bid;
    my %phrase_feature;
    # to recover the tree structure
    for my $phrase_node ($annotation_node->getElementsByTagName('Chunk')) {
	my $id = $phrase_node->getAttribute('id');
	$id =~ s/^c//;
	my $head_id = $phrase_node->getAttribute('head');
	$head_id =~ s/^c//;
	my $phrase_feature = $phrase_node->getAttribute('feature');
	$phrase_feature{$id} = $phrase_feature;

	# bnst start
	if ($phrase_feature =~ /文節:(\d+)\-(\d+)/) {
	    my $start_tid = $1;
	    my $end_tid = $2;
	    $bnst_span{$start_tid} = $end_tid;

	    $current_bnst_id++;
	    for my $id ($start_tid .. $end_tid) {
		$tid2bid{$id} = $current_bnst_id;
	    }
	}
	$parent_tid{$id} = $head_id;
    }

    for my $phrase_node ($annotation_node->getElementsByTagName('Chunk')) {
	my $id = $phrase_node->getAttribute('id');
	$id =~ s/^c//;

	my $head_id = $phrase_node->getAttribute('head');
	$head_id =~ s/^c//;
	my $dpnd_type = $phrase_node->getAttribute('type');
	my $phrase_feature = $phrase_node->getAttribute('feature');
	$phrase_feature =~ s/&lt;/</g;
	$phrase_feature =~ s/&gt;/>/g;

	# bnst info.
	if (defined $bnst_span{$id}) {
	    my $head_bnst_id = !defined $tid2bid{$parent_tid{$bnst_span{$id}}} ? '-1' : $tid2bid{$parent_tid{$bnst_span{$id}}};

	    my $bnst_feature = $phrase_feature{$bnst_span{$id}};
	    $knp_format_string .= "* $head_bnst_id$dpnd_type $bnst_feature\n";
	}

	$knp_format_string .= "+ $head_id$dpnd_type $phrase_feature\n";
	for my $word_node ($phrase_node->getElementsByTagName('Token')) {
	    my $str = $word_node->getAttribute('surf');
	    my $read = $word_node->getAttribute('read');
	    my $lem = $word_node->getAttribute('orig');

	    my $pos1 = $word_node->getAttribute('pos1');
	    $pos1 = '*' unless $pos1;
	    my $pos2 = $word_node->getAttribute('pos2');
	    $pos2 = '*' unless $pos2;
	    my $pos3 = $word_node->getAttribute('pos3');
	    $pos3 = '*' unless $pos3;
	    my $pos4 = $word_node->getAttribute('pos4');
	    $pos4 = '*' unless $pos4;

	    my $word_feature = $word_node->getAttribute('feature');
	    $word_feature =~ s/&lt;/</g;
	    $word_feature =~ s/&gt;/>/g;

	    my $repname = $word_node->getAttribute('repname');
	    my $imis = defined $repname ? "代表表記:$repname" : 'NULL';

	    # the numbers are tentative
	    $knp_format_string .= "$str $read $lem $pos1 1 $pos2 1 $pos3 1 $pos4 1 $imis $word_feature\n";

	}
    }

    $knp_format_string .= "EOS\n";
    return $knp_format_string;
}


# get the number of headword in the phrase
sub get_phrase_head_num {
    my ($words_ar) = @_;

    for my $i (reverse(0 .. $#{$words_ar})) {
	if ($words_ar->[$i]{content_p}) {
	    return $i;
	}
    }
    return $#{$words_ar}; # default is the last one in the phrase
}

1;
