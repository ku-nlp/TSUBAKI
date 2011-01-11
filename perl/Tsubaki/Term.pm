package Tsubaki::Term;

# $Id$

# 検索表現を構成する単語・句・係り受けを表すクラス

use strict;
use utf8;
use Encode;
use Configure;

my $CONFIG = Configure::get_instance();

our %TYPE2INT;
$TYPE2INT{word} = 1;
$TYPE2INT{optional_word} = 3;
$TYPE2INT{dpnd} = 3;
$TYPE2INT{force_dpnd} = 1;

sub new {
    my ($class, $params) = @_;

    my $this;
    foreach my $k (keys %$params) {
	$this->{$k} = $params->{$k};
    }

    bless $this;
}

sub show_query_structure {
    my ($this) = @_;

    if ($this->{term_type} eq 'word') {
	return $this->{text};
    } else {
	return "";
    }
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

    foreach my $k (keys %$this) {
	print $space . "- " . $k . " = " . $this->{$k} . "\n";
    }
}

sub get_term_type {
    my ($this) = @_;
    return $TYPE2INT{$this->{term_type}};
}

sub to_uri_escaped_string {
    my ($this, $rep2rep_w_yomi) = @_;

    if ($this->{term_type} eq 'word') {
	unless ($this->{text} =~ /<^>]+?>/) {
	    return $rep2rep_w_yomi->{$this->{text}};
	}
    }
    return '';
}

sub to_S_exp {
    my ($this, $space) = @_;

    my ($midasi);
    if ($CONFIG->{IS_NICT_MODE}) { # attach blocktype backward if NICT
	$midasi = sprintf ("%s%s", lc($this->{text}), $this->{blockType});
    }
    else {
	$midasi = sprintf ("%s%s", $this->{blockType}, lc($this->{text}));
    }
    return sprintf("%s((%s %d %d %d %d %d))\n", $space, $midasi, $TYPE2INT{$this->{term_type}}, $this->{gdf}, (($this->{node_type} eq 'basic')? 1 : 0), (($this->{term_type} =~ /word/) ? 0 : 1), $this->{pos});
}

sub to_S_exp_for_anchor {
    my ($this, $space) = @_;

    my ($midasi);
    if ($this->{blockType}) {
	if ($CONFIG->{IS_NICT_MODE}) { # attach blocktype backward if NICT
	    $midasi = sprintf ("%s:AC", lc($this->{text}));
	}
	else {
	    $midasi = sprintf ("AC:%s", lc($this->{text}));
	}
    }
    else {
	$midasi = lc($this->{text});
    }

    return sprintf("%s((%s %d %d %d %d))\n", $space, $midasi, 3, $this->{gdf}, (($this->{node_type} eq 'basic')? 1 : 0), (($this->{term_type} =~ /word/) ? 2 : 3));
}

sub get_id {
    my ($this) = @_;

    return sprintf "%s%s", $this->{blockType}, $this->{text};
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
