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

my $CONFIG = Configure::get_instance();

my $font_size = 12;
my $arrow_size = 3;

my @color = ();
push(@color, '#ffa500;');
push(@color, '#000080;');
push(@color, '#779977;');
push(@color, '#800000;');
push(@color, '#997799;');
push(@color, '#770000;');
push(@color, '#007700;');
push(@color, '#777700;');
push(@color, '#007777;');
push(@color, '#770077;');

my @bgcolor = ();
push(@bgcolor, '#ffff99;');
push(@bgcolor, '#bbffff;');
push(@bgcolor, '#bbffbb;');
push(@bgcolor, '#ffbbbb;');
push(@bgcolor, '#ffbbff;');
push(@bgcolor, '#bb0000;');
push(@bgcolor, '#00bb00;');
push(@bgcolor, '#bbbb00;');
push(@bgcolor, '#00bbbb;');
push(@bgcolor, '#bb00bb;');

my @stylecolor = ();
push(@stylecolor, 'border: 2px solid #ffa500; background-color: #ffff99;');
push(@stylecolor, 'border: 2px solid #000080; background-color: #bbffff;');
push(@stylecolor, 'border: 2px solid #779977; background-color: #bbffbb;');
push(@stylecolor, 'border: 2px solid #800000; background-color: #ffbbbb;');
push(@stylecolor, 'border: 2px solid #997799; background-color: #ffbbff;');
push(@stylecolor, 'border: 2px solid #770000; background-color: #bb0000; color: white;');
push(@stylecolor, 'border: 2px solid #007700; background-color: #00bb00; color: white;');
push(@stylecolor, 'border: 2px solid #777700; background-color: #bbbb00; color: white;');
push(@stylecolor, 'border: 2px solid #007777; background-color: #00bbbb; color: white;');
push(@stylecolor, 'border: 2px solid #770077; background-color: #bb00bb; color: white;');

my $removedcolor = 'border: 2px solid #9f9f9f; background-color: #e0e0e0; color: black;';


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


sub show_query_structure {
    my ($this) = @_;



    if ($this->{isRoot}) {
	foreach my $child (@{$this->{children}}) {
	    $child->show_query_structure();
	}
    } else {
	foreach my $term (@{$this->{terms}}) {
	    print $term->{text} . "<BR>\n";
	}

	if ($this->{hasChild}) {
	    foreach my $child (@{$this->{children}}) {
		$child->show_query_structure();
	    }
	}
    }

    return "";
















    my $buf;
    my $num = ($this->{hasChild}) ? scalar (@{$this->{children}}) : 0;

    my $CONFIG = Configure::get_instance();
    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.cdb\n";

    foreach my $term (@{$this->{terms}}) {
	my ($id) = ($term->{groupID} =~ /^\d+\-(\d+)/);
	my $string = $term->show_query_structure();
	if ($term->{node_type} eq 'syn') {
	    my $_string = decode('utf8', $synonyms{$string});
	    next if ($_string eq '');
	    $string = $_string;
	}
	foreach my $_string (split (/\|/, $string)) {
	    $_string =~ s/\[.+?\]//g;
	    if ($num > 1) {
		$buf .= ("<TR><TD colspan='$num' align=center style='vertical-align:top; padding:0.5em; border: 1px solid green;$stylecolor[$id];'>" . $_string . "</TD></TR>\n");
	    } else {
		$buf .= ("<TR><TD align=center style='vertical-align:top; padding:0.5em; border: 1px solid green;$stylecolor[$id];'>" . $_string . "</TD></TR>\n");
	    }
	}
    }

    if ($this->{hasChild}) {
	my $_buf = "<TR>";
	my $rate = 100 / $num;
	foreach my $child (sort {$a->{tid} <=> $b->{tid}} @{$this->{children}}) {
	    $_buf .= ("<TD valign='top' align='center' width='$rate\%'>" . $child->show_query_structure() . "</TD>");
	}
	$_buf .= "</TR>";
	$buf = $_buf . $buf;
    }


    my ($id) = ($this->{groupID} =~ /^\d+\-(\d+)/);
    return sprintf qq(<TABLE style="vertical-align:top; padding:0.5em; border: 1px solid red; %s">($id) $buf</TABLE>\n), $stylecolor[$id];
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
