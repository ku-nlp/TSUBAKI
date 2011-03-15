package Tsubaki::TermGroup;

# $Id$

# 検索表現を構成する単語・句・係り受けを表すクラス

use strict;
use utf8;
use Encode;
use Tsubaki::Term;
use Data::Dumper;
use Configure;
use CDB_Reader;
use URI::Escape;


my $CONFIG = Configure::get_instance();


sub new {
    my ($class, $gid, $pos, $gdf, $parentGroup, $basic_node, $synnodes, $parent, $children, $opt) = @_;

    my $this;
    $this->{hasChild} = (defined $children) ? 1 : 0;
    $this->{children} = $children;
    $this->{parentGroup} = $parentGroup;
    $this->{groupID} = $gid;
    $this->{discrete_level} = 1;
    $this->{search_type} = $opt->{search_type};
    $this->{proximity_size} = $opt->{proximity_size};
    if ($opt->{isRoot}) {
	$this->{optionals} = $opt->{optionals};
	$this->{result} = $opt->{result};
	$this->{isRoot} = $opt->{isRoot};
	$this->{condition} = $opt->{condition};
	$this->{rep2style} = $opt->{rep2style};
	$this->{rep2rep_w_yomi} = $opt->{rep2rep_w_yomi};
	$this->{synnode2midasi} = $opt->{synnode2midasi};
    } else {
	$this->{gdf} = $gdf;
	&pushbackTerms ($this, $basic_node, $synnodes, $gid, $pos, $opt);
    }

    bless $this;
}

sub pushbackTerms {
    my ($this, $basic_node, $synnodes, $gid, $pos, $opt) = @_;

    my $cnt = 0;
    my %alreadyPushedTexts = ();

    # 利用するブロックタイプの取得
    my $blockTypes = ();
    if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
	$blockTypes = $opt->{option}{blockTypes};
    } else {
	$blockTypes->{UNDEF} = 1;
    }

    foreach my $midasi (@$synnodes) {
	next if (exists $alreadyPushedTexts{$midasi});
	$alreadyPushedTexts{$midasi} = 1;

	foreach my $tag (keys %$blockTypes) {
	    my $term = new Tsubaki::Term ({
		tid => sprintf ("%s-%s", $gid, $cnt++),
		pos => $pos,
		text => $midasi,
		term_type => (($opt->{optional_flag}) ? 'optional_word' : 'word'),
		node_type => ($midasi eq $basic_node) ? 'basic' : 'syn',
		gdf => $this->{gdf},
		blockType => (($tag eq 'UNDEF') ? undef : $tag)
#		blockType => $CONFIG->{BLOCK_TYPE_DATA}{$tag}{featureBit}
					      });
	    push (@{$this->{terms}}, $term);
	}
    }
}

sub terms {
    my ($this) = @_;

    return $this->{terms};
}

sub appendChild {
    my ($this, $child) = @_;
    $this->{hasChild} = 1;

    push (@{$this->{children}}, $child);
}

sub children {
    my ($this) = @_;

    return $this->{children};
}

sub hasChild {
    my ($this) = @_;

    return $this->{hasChild};
}

sub parent {
    my ($this) = @_;

    return $this->{parent};
}

sub term_id {
    my ($this) = @_;

    return $this->{term_id};
}

sub discrete_level {
    my ($this) = @_;

    return $this->{discrete_level};
}

sub text {
    my ($this) = @_;

    return $this->{text};
}

sub qtf {
    my ($this) = @_;

    return $this->{qtf};
}

sub gdf {
    my ($this) = @_;

    return $this->{gdf};
}

sub to_string {
    my ($this, $space) = @_;

    print $space . "* gdf = " . $this->{gdf} . "\n";
    print $space . "* group id = " . $this->{groupID} . "\n";
    print $space . "* discrete level = " . $this->{discrete_level} . "\n";
    foreach my $term (@{$this->{terms}}) {
	$term->to_string ($space . "  ");
	print "\n";
    }

    foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	$child->to_string($space . "\t");
    }
    print "\n";
}

sub to_uri_escaped_string {
    my ($this, $rep2rep_w_yomi) = @_;

    if ($this->{isRoot}) {
	my @buf;
	foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	    push (@buf, $child->to_uri_escaped_string($this->{rep2rep_w_yomi}));
	}
	return &uri_escape(encode('utf8', join (",", @buf)));
    } else {
	my %buf = ();
	foreach my $term (@{$this->{terms}}) {
	    $buf{$term->to_uri_escaped_string($rep2rep_w_yomi)} = 1;
	}
	if ($this->{hasChild}) {    
	    foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
		$buf{$child->to_uri_escaped_string($rep2rep_w_yomi)} = 1;
	    }
	}

	return join (";", keys %buf);
    }
}

sub get_term_type {
    my ($this) = @_;

    if (defined $this->{terms}[0]) {
	return $this->{terms}[0]->get_term_type();
    } else {
	return 10;
    }
}

sub _to_S_exp_for_ROOT {
    my ($this, $indent) = @_;

    my ($S_exp, $_S_exp, $_S_exp_for_anchor, $num_of_children);
    my @_children = ();
    if ($this->{condition}{is_phrasal_search} > 0) {
	@_children = sort {$a->get_term_type() <=> $b->get_term_type() || $a->{pos} <=> $b->{pos}} @{$this->{children}};
    } else {
	@_children = sort {$a->get_term_type() <=> $b->get_term_type() || $a->{gdf} <=> $b->{gdf}} @{$this->{children}};
    }

    foreach my $child (@_children) {
	$_S_exp .= $child->to_S_exp($indent, $this->{condition});
	$_S_exp_for_anchor .= $child->to_S_exp_for_anchor($indent);
	$num_of_children++;
    }

    if ($num_of_children > 1) {
	$_S_exp = sprintf ("(%s %s)", &_getOperationTag($this->{condition}), $_S_exp);
    }

    # optional要素の書き出し
    my @buf;
    while (my ($key, $node) = each %{$this->{optionals}}) {
	push (@buf, $node->to_S_exp($indent, $this->{condition}));
    }

    if (scalar(@buf)) {
	$S_exp = sprintf ("(ROOT %s %s %s )", $_S_exp, join (" ", @buf), $_S_exp_for_anchor);
    } else {
	$S_exp = sprintf ("(ROOT %s %s )", $_S_exp, $_S_exp_for_anchor);
    }

    return $S_exp;
}

sub _to_S_exp {
    my ($this, $indent, $condition) = @_;

    my $is_single_node = (!$this->{hasChild} && scalar(@{$this->{terms}}) < 2);
    my $_indent = ($is_single_node) ? $indent : $indent . "\t";

    my $S_exp;
    $S_exp .= "$indent(OR\n" unless ($is_single_node);
    foreach my $term (@{$this->{terms}}) {
	$S_exp .= $term->to_S_exp ($_indent, $condition);
    }

    if ($this->{hasChild}) {
	my $operationTag = &_getOperationTag ($condition);
	$S_exp .= (($is_single_node) ? "$indent($operationTag\n" : "\t$indent($operationTag\n");

	my $_indent = ($is_single_node) ? $indent . "\t" : $indent . "\t\t";
	foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	    $S_exp .= $child->to_S_exp($_indent, $condition);
	}

	$S_exp .= (($is_single_node) ? "$indent)\n" : "\t$indent)\n");
    }
    $S_exp .= "$indent)\n" unless ($is_single_node);

    return $S_exp;
}

sub _getOperationTag {
    my ($condition) = @_;

    my $operationTag;
    if ($condition->{is_phrasal_search} > 0) {
	$operationTag = 'PHRASE';
    } elsif ($condition->{approximate_dist} > 0) {
	if ($condition->{approximate_order}) {
	    $operationTag = sprintf ("ORDERED_PROX %d", $condition->{approximate_dist});
	} else {
	    $operationTag = sprintf ("PROX %d", $condition->{approximate_dist});
	}
    } else {
	$operationTag = 'AND';
    }

    return $operationTag;
}

sub to_S_exp {
    my ($this, $indent, $condition) = @_;

    my $S_exp;
    if ($this->{isRoot}) {
	return $this->_to_S_exp_for_ROOT ($indent);
    } else {
	return $this->_to_S_exp ($indent, $condition);
    }
}

sub to_S_exp_for_anchor {
    my ($this, $indent) = @_;


    my $is_single_node = (!$this->{hasChild} && scalar(@{$this->{terms}}) < 2);
    my $S_exp;
    $S_exp .= "$indent(OR\n" unless ($is_single_node);
    my %buf;
    foreach my $term (@{$this->{terms}}) {
	unless (exists $buf{$term->{text}}) {
	    $S_exp .= $term->to_S_exp_for_anchor (" ");
	    $buf{$term->{text}} = 1;
	}
    }
    $S_exp .= "$indent)\n" unless ($is_single_node);

    if ($this->{hasChild}) {
#	$S_exp .= (($is_single_node) ? "$indent(AND\n" : "\t$indent(AND\n");
#	my $_indent = ($is_single_node) ? $indent . "\t" : $indent . "\t\t";
	foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	    $S_exp .= $child->to_S_exp_for_anchor(" ");
	}
#	$S_exp .= (($is_single_node) ? "$indent)\n" : "\t$indent)\n");
    }
#    $S_exp .= "$indent)\n" unless ($is_single_node);

    return $S_exp;
}

-1;
