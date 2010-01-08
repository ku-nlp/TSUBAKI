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

    my $CONFIG = Configure::get_instance();

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

    # 基本句配列中での位置
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
	next if (exists $alreadyPushedTexts{$text_wo_yomi});
	$alreadyPushedTexts{$text_wo_yomi} = 1;

	push (@{$this->{terms}}, new Tsubaki::Term ({
		  tid => sprintf ("%s-%s", $gid, $cnt++),
		  text => $text_wo_yomi,
		  term_type => 'word',
		  node_type => ($synnode eq $basic_node) ? 'basic' : 'syn'
	      })
	    );
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

    foreach my $child (@{$this->{children}}) {
	$child->to_string($space . "\t");
    }
    print "\n";
}

sub to_S_exp {
    my ($this, $space) = @_;

    my $S_exp;
    if ($this->{isRoot}) {
	my $_S_exp;
	foreach my $child (@{$this->{children}}) {
	    $_S_exp .= $child->to_S_exp($space);
	}

	if (scalar(keys %{$this->{optionals}}) > 1) {
	    my @buf;
	    while (my ($k, $v) = each %{$this->{optionals}}) {
		push (@buf, $v->to_S_exp());
	    }
	    $S_exp = sprintf ("(ROOT (%s (%s)))", $_S_exp, join (" ", @buf));
	} else {
	    $S_exp = sprintf ("(ROOT (%s))", $_S_exp);
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
	    foreach my $child (@{$this->{children}}) {
		$S_exp .= $child->to_S_exp($_space);
	    }
	    $S_exp .= (($is_single_node) ? "$space)\n" : "\t$space)\n");
	}
	$S_exp .= "$space)\n" unless ($is_single_node);
    }

    return $S_exp;
}




#     $this->{kihonku} = $kihonkus->[$j];
#     $this->{synNodes} = $SYNNODES;
#     $this->{hasSynNodes} = (defined $SYNNODES) ? 1 : 0;
#     $this->{basicNodes} = undef;
#     $this->{hasBasicNodes} = 0;
#     $this->{synnodeInfo} = $SYN_INFO;
#     $this->{df} = -1;
#     $this->{requisite} = 1;
#     $this->{optional} = 0;

#     # HTMLコード生成用
#     $this->{x} = 0;
#     $this->{y} = 0;

#     if ($i == $j) {
# 	$this->{hasChild} = 0;
# 	$this->{children} = [];
# 	$this->{hasBasicNodes} = 1;

# 	# 基本ノードとSYNノードに分解する
# 	my @basicNodes;
# 	my @synNodes;
# 	foreach my $synnode (@$SYNNODES) {
# 	    if ($synnode->synid =~ /s\d+/) {
# 		push(@synNodes, $synnode);
# 	    } else {
# 		push(@basicNodes, $synnode);
# 	    }		
# 	}
# 	$this->{basicNodes} = \@basicNodes;
# 	$this->{synNodes} = \@synNodes;
#     } else {
# 	my @child_nodes;
# 	for (my $k = $j; $k > $i - 1; $k--) {
# 	    next if (defined $CHILD_NODE_IDS && !exists $CHILD_NODE_IDS->{$k});

# 	    # $k番目の基本句を末尾にもつ、もっとも大きなSYNノードを探索
# 	    my $buf = &seekTheLargestSynNode($kihonkus->[$k], $ANCESTOR_IDS, $i);

# 	    # $k番目の基本句を末尾にもつ、複数ノードにまたがるSYNノードがない
# 	    if ($buf->{num} == 1) {
# 		unshift (@child_nodes, new Tsubaki::QTerm($kihonkus, $k, $k, undef, undef, $buf->{synnodeInfo}, $buf->{synnodes}));
# 	    }
# 	    # $k番目の基本句を末尾にもつ、複数ノードにまたがるSYNノードがある
# 	    else {
# 		# SYNノードでカバーされるSYNIDの取得
# 		my %child_ids = ();
# 		foreach my $id (@{$buf->{ids}}) {
# 		    $child_ids{$id} = 1;
# 		}

# 		# 自身がカバーしているノードをTERMオブジェクトにする
# 		$ANCESTOR_IDS->{$buf->{id}} = 1;
# 		unshift (@child_nodes, new Tsubaki::QTerm($kihonkus, $buf->{ids}[0], $buf->{ids}[-1], \%child_ids, $ANCESTOR_IDS, $buf->{synnodeInfo}, $buf->{synnodes}));
# 		delete($ANCESTOR_IDS->{$buf->{id}});

# 		# $k-- の分を足す
# 		$k = $k - $buf->{num} + 1;
# 	    }
# 	}

# 	# 子供を持っていることを記録
# 	$this->{hasChild} = 1;
# 	$this->{children} = \@child_nodes;
#     }

#     bless $this;
# }

# sub DESTROY {
# }


# # 		# ids の値が連続してない場合は、飛んでる部分の Term を作成（このTermは兄弟ノード）
# # 		for (my $k = scalar(@{$buf->{ids}}) - 1; $k > 0; $k--) {
# # 		    if ($buf->{ids}[$k] - $buf->{ids}[$k - 1] > 1) {
# # 			my $l = $buf->$buf->{ids}[$k - 1] + 1;
# # 			my $m = $buf->$buf->{ids}[$k];

# # 			unshift (@child_nodes, new Term($kihonkus, $l, $m, $ANCESTOR_IDS, undef));
# # 		    }
# # 		}

# sub getDF {
#     my ($this) = @_;

#     return $this->{df};
# }

# sub setDF {
#     my ($this, $dfdb) = @_;

#     if ($this->hasChild) {
# 	my @buf;
# 	foreach my $child ($this->childNodes) {
# 	    $child->setDF($dfdb);
# 	}
#     }

#     if ($this->hasBasicNodes) {
# 	foreach my $node ($this->basicNodes) {
# 	    $this->{df} = &get_DF($node->synid, $dfdb);
# 	    last;
# 	}
#     }
#     elsif ($this->hasSynNodes) {
# 	foreach my $node ($this->synNodes) {
# 	    $this->{df} = &get_DF($node->synid, $dfdb);
# 	    last;
# 	}
#     }	
# }


# sub get_DF {
#     my ($k, $DFDBs) = @_;

#     $k =~ s/\/.+$//;
#     print $k . "<BR>\n";

#     my $k_utf8 = encode('utf8', $k);
#     my $gdf = 0;
# #   my $DFDBs = (index($k, '->') > 0) ? $this->{DFDBS_DPND} : $this->{DFDBS_WORD};
#     foreach my $dfdb (@{$DFDBs}) {
# 	my $val = $dfdb->{$k_utf8};
# 	if (defined $val) {
# 	    $gdf += $val;
#  	    last;
#  	}
#     }
#     return $gdf;
# }

# sub seekTheLargestSynNode {
#     my ($kihonku, $ANCESTOR_IDS, $front) = @_;

#     my $buf = undef;
#     foreach my $synnodes ($kihonku->synnodes) {
# 	next if (exists $ANCESTOR_IDS->{$synnodes->tagid});

# 	my @ids = split(/,/, $synnodes->tagid);
# 	next if ($ids[0] < $front);

# 	my $num = scalar(@ids);
# 	unless (defined $buf) {
# 	    push(@{$buf->{synnodes}}, $synnodes->synnode);
# 	    $buf->{num} = $num;
# 	    $buf->{ids} = \@ids;
# 	    $buf->{id} = $synnodes->tagid;
# 	    $buf->{synnodeInfo} = $synnodes;
# 	} else {
# 	    if ($num > $buf->{num}) {
# 		$buf->{synnodes} = [];
# 		push(@{$buf->{synnodes}}, $synnodes->synnode);
# 		$buf->{num} = $num;
# 		$buf->{ids} = \@ids;
# 		$buf->{id} = $synnodes->tagid;
# 		$buf->{synnodeInfo} = $synnodes;
# 	    }
# 	}
#     }

#     return $buf;
# }


# sub toString {
#     my ($this, $level) = @_;

#     if ($this->{hasChild}) {
# 	foreach my $child (@{$this->{children}}) {
# 	    $child->toString($level + 1);
# 	}
#     }

#     if (defined $this->synNodes) {
# 	my $indent;
# 	for (my $i = 0; $i < $level; $i++) {
# 	    $indent .=  "  ";
# 	}
# 	print $indent . $this->{kihonku}->fstring . "\n";
# 	print $indent . $this->{synnodeInfo}->tagid . ' ' . $this->{synnodeInfo}->parent . $this->{synnodeInfo}->dpndtype . ' ' . $this->{synnodeInfo}->midasi . ' ' . $this->{synnodeInfo}->feature . "\n";
# 	foreach my $synnode ($this->synNodes) {
# 	    print $indent;
# 	    foreach my $k (sort keys %$synnode) {
# 		my $v = ((ref $synnode->{$k}) =~ /ARRAY/) ? join(",", @{$synnode->{$k}}) : $synnode->{$k};
# 		next if ($v eq '');

# 		print $k . "=" . $v . ",";
# 	    }
# 	    print "\n";
# 	}
# 	print "\n";
#     }
# }

# sub hasChild {
#     my ($this) = @_;
#     return $this->{hasChild};
# }

# sub childNodes {
#     my ($this) = @_;

#     return @{$this->{children}};
# }

# sub hasSynNodes {
#     my ($this) = @_;

#     return $this->{hasSynNodes};
# }

# sub synNodes {
#     my ($this) = @_;

#     if (defined $this->{synNodes}) {
# 	return @{$this->{synNodes}};
#     } else {
# 	return undef;
#     }
# }

# sub hasBasicNodes {
#     my ($this) = @_;

#     return $this->{hasBasicNodes};
# }

# sub basicNodes {
#     my ($this) = @_;

#     return @{$this->{basicNodes}};
# }

# sub isRequisiteNode {
#     my ($this) = @_;

#     return $this->{requisite};
# }

# sub isOptionalNode {
#     my ($this) = @_;

#     return $this->{optional};
# }

# sub toHTMLCode {
#     my ($this) = @_;

#     if ($this->hasChild) {
# 	foreach my $child ($this->childNodes) {
# 	    $child->toHTMLCode();
# 	}
#     }

#     # 見出し（出現形）
#     my $midasi;
#     if ($this->hasBasicNodes) {
# 	my $buf = $this->{synnodeInfo}->midasi;
# 	$midasi = sprintf qq(<DIV class="midasi">%s</DIV>), $buf;
#     }

#     # 基本ノード
#     my $basicNodeString;
#     if ($this->hasBasicNodes) {
# 	my @buf = ();
# 	foreach my $node ($this->basicNodes) {
# 	    push (@buf, sprintf qq(<DIV class="basicNode">%s</DIV>), $node->synid);
# 	}
# 	$basicNodeString = join ("\n", @buf);
#     }

#     # SYNノード
#     my $synNodeString;
#     if ($this->hasSynNodes) {
# 	my @synnodes = ();
# 	foreach my $synnode ($this->synNodes) {
# 	    push (@synnodes, sprintf qq(<DIV class="synNode">%s</DIV>), $synnode->synid);
# 	}
# 	$synNodeString = join ("\n", @synnodes);
#     }


#     # HTMLコードを生成
#     my $color = ($this->isRequisiteNode) ? "blue" : "red";
#     printf qq(<DIV style="width: %sem; border: 1px solid $color; position: absolute; top: %sem; left: %sem;" class="group">\n), $this->{width}, $this->{y}, $this->{x};
#     print $midasi . "\n";
#     print $basicNodeString . "\n";
#     print $synNodeString . "\n";
#     print $this->getDF;
#     print "</DIV>\n";
# }

# sub calculatePosition {
#     my ($this, $offsetX, $offsetY, $PROPERTY) = @_;

#     my ($max_width, $max_height) = (0, 0);
#     if ($this->hasChild) {
# 	my $off_x = $offsetX;
# 	foreach my $child ($this->childNodes) {
# 	    my ($w, $h) = $child->calculatePosition($off_x, $offsetY, $PROPERTY);
# 	    $max_width += $w;
# 	    $off_x += $w;
# 	    $max_height = $h if ($max_height < $h);
# 	}
# #	$max_width -= $PROPERTY->{margin};
#     }
#     $offsetY += $max_height;



#     ##############
#     # 自身について
#     ##############

#     my $num_of_lines = 0;

#     # 見出し（出現形）
#     if ($this->hasBasicNodes) {
# 	my $buf = $this->{synnodeInfo}->midasi;
# 	my $length_of_string = length($buf);
# 	$max_width = length($buf) if ($max_width < length($buf));
# 	$num_of_lines++;
#     }

#     # 基本ノード
#     if ($this->hasBasicNodes) {
# 	foreach my $node ($this->basicNodes) {
# 	    $max_width = length($node->synid) if ($max_width < length($node->synid));
# 	    $num_of_lines++;
# 	}
#     }

#     # SYNノード
#     if ($this->hasSynNodes) {
# 	foreach my $synnode ($this->synNodes) {
# 	    $max_width = length($synnode->synid) if ($max_width < length($synnode->synid));
# 	    $num_of_lines++;
# 	}
#     }

#     $max_width += $PROPERTY->{margin};
#     $max_height += ($num_of_lines + ($num_of_lines * $PROPERTY->{line_height}) + $PROPERTY->{margin});


#     # 座標の保存2
#     # 座標の保存1
#     $this->{x} = $offsetX;
#     $this->{y} = $offsetY;
#     $this->{width} = $max_width;
#     $this->{height} = $max_height;

#     return ($max_width, $max_height);
# }


# sub toQList {
#     my ($this, $INDENT) = @_;

#     my $str_of_childnodes;
#     if ($this->hasChild) {
# 	my @buf;
# 	foreach my $child (sort {$a->getDF() <=> $b->getDF()} $this->childNodes) {
# 	    push(@buf, $child->toQList($INDENT));
# 	}

# 	$str_of_childnodes .= sprintf "<DIV style='padding-left:${INDENT}em; border: 0px solid red;'>AND ( " . join(',', @buf) . " )</DIV>";
# 	$str_of_childnodes =~ s!</DIV>,!,</DIV>!g;
#     }


#     my @buf;
#     if (defined $this->{basicNodes}) {
# 	foreach my $node (@{$this->{basicNodes}}) {
# 	    push (@buf, $node->synid);
# 	}
#     }

#     if (defined $this->{synNodes}) {
# 	foreach my $synnode (@{$this->{synNodes}}) {
# 	    push (@buf, $synnode->synid);
# 	}
#     }

#     my $df = $this->getDF();
#     my $str_of_self = sprintf "<DIV style='padding-left:${INDENT}em; border: 0px solid red;'>";
#     if (scalar(@buf) > 1) {
# 	$str_of_self .= "OR ( " . (join (",&nbsp;", @buf)) . " )";
#     } else {
# 	$str_of_self .= (join (",&nbsp;", @buf));
#     }
#     $str_of_self .= sprintf "[$df]</DIV>";

#     if ($str_of_childnodes ne '') {
# 	$str_of_self =~ s!</DIV>$!,</DIV>!;
# 	return "<DIV style='padding-left:${INDENT}em; border: 0px solid red;'>OR ( $str_of_self $str_of_childnodes )</DIV>";
#     } else {
# 	return $str_of_self;
#     }
# }


# sub toQList2 {
#     my ($this, $INDENT) = @_;

#     my $str;
#     if ($this->hasChild) {
# 	my @buf;
# 	foreach my $child ($this->childNodes) {
# 	    push(@buf, $INDENT . $child->toQList());
# 	}

# 	$str .= (join ($INDENT . "AND\n", @buf));
#     }

#     if (defined $this->{synnodes}) {
# 	my @buf;
# 	foreach my $synnode (@{$this->{synnodes}}) {
# 	    push (@buf, $synnode->synid);
# 	}
# 	$str .= sprintf "[" . (join ("&nbsp;OR&nbsp;", @buf)) . "]";
# 	return "($str)<P>";
#     } else {
# 	return "$str<P>\n";
#     }

# }

# sub toQList_bak {
#     my ($this) = @_;

#     my $str;
#     if ($this->hasChild) {
# 	my @buf;
# 	foreach my $child (@{$this->childNodes}) {
# 	    push(@buf, $child->toQList());
# 	}

# 	$str .= (scalar(@buf) > 1) ? sprintf "(" . (join ("&nbsp;AND&nbsp;", @buf)) . ")" : sprintf "(" . (join ('', @buf)) . ")";
# 	$str .= sprintf "&nbsp;OR&nbsp;" if (defined $this->{synnodes});
#     }

#     if (defined $this->{synnodes}) {
# 	my @buf;
# 	foreach my $synnode (@{$this->{synnodes}}) {
# 	    push (@buf, $synnode->synid);
# 	}
# 	$str .= sprintf "[" . (join ("&nbsp;OR&nbsp;", @buf)) . "]";
# 	return "($str)<P>";
#     } else {
# 	return "$str<P>\n";
#     }

# }

-1;
