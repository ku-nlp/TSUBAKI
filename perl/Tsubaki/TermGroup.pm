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


sub getBasicNode {
    my ($synnodes) = @_;

    foreach my $synnode (@$synnodes) {
	if ($synnode->synid !~ /^s\d+/ && $synnode->feature eq '') {
	    return $synnode;
	}
    }
    return undef;
}

sub remove_yomi {
    my ($text) = @_;

    my @buf;
    foreach my $word (split /\+/, $text) {
	my ($hyouki, $yomi) = split (/\//, $word);
	push (@buf, $hyouki);
    }

    return join ("+", @buf)
}


sub new {
    my ($class, $gid, $parentGroup, $synnodes, $tagids, $children, $parent, $opt) = @_;

    my $this;
    $this->{children} = $children;
    $this->{hasChild} = ($children) ? 1 : 0;
    $this->{parentGroup} = $parentGroup;
    $this->{groupID} = $gid;
    $this->{discrete_level} = 1;
    $this->{isRoot} = $opt->{isRoot};
    if ($opt->{isRoot}) {
	$this->{optionals} = $opt->{optionals};
    }
    my $CONFIG = Configure::get_instance();

    # 蝓ｺ譛ｬ蜿･驟榊�荳ｭ縺ｧ縺ｮ菴咲ｽｮ
    $this->{position} = $tagids;

    my $basic_node = &getBasicNode($synnodes);

    # $UTIL->getGDF($basic_node->synid);
    my $DFDBS_WORD = new CDB_Reader (sprintf ("%s/df.word.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
    if ($basic_node) {
	$this->{gdf} = $DFDBS_WORD->get(encode ('utf8', &remove_yomi($basic_node->synid)));
    } else {
	$this->{gdf} = $DFDBS_WORD->get(encode ('utf8', &remove_yomi($synnodes->[0]->synid))) if (defined $synnodes);
    }

    my $cnt = 0;
    my %alreadyPushedTexts = ();
    foreach my $synnode (@$synnodes) {
	my $text_wo_yomi = sprintf ("%s%s", &remove_yomi($synnode->synid), $synnode->feature);

	# 文法素性の削除
	$text_wo_yomi =~ s/<可能>//;
	$text_wo_yomi =~ s/<尊敬>//;
	$text_wo_yomi =~ s/<受身>//;
	$text_wo_yomi =~ s/<使役>//;

	next if (exists $alreadyPushedTexts{$text_wo_yomi});
	$alreadyPushedTexts{$text_wo_yomi} = 1;

	if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
	    foreach my $tag (keys %{$opt->{option}{blockTypes}}) {
		my $term = new Tsubaki::Term ({
		    tid => sprintf ("%s-%s", $gid, $cnt++),
		    text => $text_wo_yomi,
		    term_type => (($opt->{optional_flag}) ? 'optional_word' : 'word'),
		    node_type => ($synnode eq $basic_node) ? 'basic' : 'syn',
		    gdf => $this->{gdf},
		    blockType => $tag
					      });
		push (@{$this->{terms}}, $term);
	    }
	} else {
	    my $term = new Tsubaki::Term ({
		tid => sprintf ("%s-%s", $gid, $cnt++),
		text => $text_wo_yomi,
		term_type => (($opt->{optional_flag}) ? 'optional_word' : 'word'),
		node_type => ($synnode eq $basic_node) ? 'basic' : 'syn',
		gdf => $this->{gdf}
					  });
	    push (@{$this->{terms}}, $term);
	}
    }

    bless $this;
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
    print $space . "* position = " . join(", ", @{$this->{position}}) . "\n";
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

sub to_S_exp {
    my ($this, $space) = @_;

    my $S_exp;
    if ($this->{isRoot}) {
	my $_S_exp;
	my $_S_exp_for_anchor;
	my $num_of_children = 0;
	foreach my $child (sort {$a->get_term_type() <=> $b->get_term_type() || $a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	    $_S_exp .= $child->to_S_exp($space);
	    $_S_exp_for_anchor .= $child->to_S_exp_for_anchor($space);
	    $num_of_children++;
	}
	if ($num_of_children > 1) {
	    $_S_exp = sprintf ("(AND %s)", $_S_exp);
	}	    



	my @buf;
	while (my ($k, $v) = each %{$this->{optionals}}) {
	    push (@buf, $v->to_S_exp());
	}

#	$_S_exp_for_anchor = '';
	if (scalar(@buf)) {
	    $S_exp = sprintf ("(ROOT %s %s %s )", $_S_exp, join (" ", @buf), $_S_exp_for_anchor);
	} else {
	    $S_exp = sprintf ("(ROOT %s %s )", $_S_exp, $_S_exp_for_anchor);
	}
    } else {
	my $is_single_node = (!$this->{hasChild} && scalar(@{$this->{terms}}) < 2);
	$S_exp .= "$space(OR\n" unless ($is_single_node);
	my $_space = ($is_single_node) ? $space : $space . "\t";
	foreach my $term (@{$this->{terms}}) {
	    $S_exp .= $term->to_S_exp ($_space);
	}

	if ($this->{hasChild}) {
	    $S_exp .= (($is_single_node) ? "$space(AND\n" : "\t$space(AND\n");
	    my $_space = ($is_single_node) ? $space . "\t" : $space . "\t\t";
	    foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
		$S_exp .= $child->to_S_exp($_space);
	    }
	    $S_exp .= (($is_single_node) ? "$space)\n" : "\t$space)\n");
	}
	$S_exp .= "$space)\n" unless ($is_single_node);
    }

    return $S_exp;
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
    my ($this, $space) = @_;

    my $S_exp;
    my %buf;
    foreach my $term (@{$this->{terms}}) {
	unless (exists $buf{$term->{text}}) {
	    $S_exp .= $term->to_S_exp_for_anchor (" ");
	    $buf{$term->{text}} = 1;
	}
    }

    if ($this->{hasChild}) {
#	$S_exp .= (($is_single_node) ? "$space(AND\n" : "\t$space(AND\n");
#	my $_space = ($is_single_node) ? $space . "\t" : $space . "\t\t";
	foreach my $child (sort {$a->{gdf} <=> $b->{gdf}} @{$this->{children}}) {
	    $S_exp .= $child->to_S_exp_for_anchor(" ");
	}
#	$S_exp .= (($is_single_node) ? "$space)\n" : "\t$space)\n");
    }
#    $S_exp .= "$space)\n" unless ($is_single_node);

    return $S_exp;
}

-1;
