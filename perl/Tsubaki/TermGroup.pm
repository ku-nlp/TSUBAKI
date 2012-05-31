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
our $INDENT_CHAR = "   ";

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

# termの追加
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

	my $blockTypeFeature = 0;
	foreach my $tag (keys %{$blockTypes}) {
	    $tag =~ s/://;
	    $blockTypeFeature += $CONFIG->{BLOCK_TYPE_DATA}{$tag}{mask};
	}

	my $term = new Tsubaki::Term ({
	    tid => sprintf ("%s-%s", $gid, $cnt++),
	    pos => $pos,
	    text => $midasi,
	    term_type => (($opt->{optional_flag}) ? 'optional_word' : 'word'),
	    node_type => ($midasi eq $basic_node) ? 'basic' : 'syn',
	    gdf => $this->{gdf},
	    # 最後の基本句から抽出されたタームかどうか
	    is_last_kihonku => $opt->{is_last_kihonku},
	    blockTypeFeature => $blockTypeFeature
					      });
	push (@{$this->{terms}}, $term);
    }
}

# S式を作成するためのインターフェース
sub to_S_exp {
    my ($this, $indent, $condition, $opt, $call_for_anchor) = @_;

    if ($this->{isRoot}) {
	return $this->_to_S_exp_for_ROOT ($INDENT_CHAR, $opt);
    } else {
	return $this->_to_S_exp ($indent, $condition, $opt, $call_for_anchor);
    }
}

# ROOT用にS式を作成
sub _to_S_exp_for_ROOT {
    my ($this, $indent, $opt) = @_;

    my $call_for_anchor = 1;
    my ($_S_exp_for_body, $_S_exp_for_anchor, $num_of_children);

    # 子要素をソートするキー
    my $sortKey = ($this->{condition}{is_phrasal_search} > 0) ? 'pos' : 'gdf';
    # 子要素についてS式を作成
    foreach my $child (sort {$a->get_term_type() <=> $b->get_term_type() ||
				 $a->{$sortKey} <=> $b->{$sortKey}} @{$this->{children}}) {
	$_S_exp_for_body   .= $child->to_S_exp (($indent . $INDENT_CHAR), $this->{condition}, $opt);
	$_S_exp_for_anchor .= $child->to_S_exp ($indent, $this->{condition}, $opt, $call_for_anchor);
	$num_of_children++;
    }

    # 子要素のS式をまとめあげる
    if ($num_of_children > 1) {
	$_S_exp_for_body = sprintf ("%s(%s\n%s%s)\n",
				    $indent,
				    &_getOperationTag($this->{condition}),
				    $_S_exp_for_body,
				    $indent );
    }

    # optional要素についてS式を作成
    my @optional;
    while (my ($key, $node) = each %{$this->{optionals}}) {
	push (@optional, $node->to_S_exp($indent, $this->{condition}, $opt));
	push (@optional, $node->to_S_exp($indent, $this->{condition}, $opt, $call_for_anchor));
    }

    # ROOTに関するS式を作成
    if (scalar(@optional)) {
	return sprintf ("(ROOT\n%s%s%s)",
			$_S_exp_for_body,
			join ("", @optional),
			$_S_exp_for_anchor);
    } else {
	return sprintf ("(ROOT\n%s%s)", $_S_exp_for_body, $_S_exp_for_anchor);
    }
}

# S式を作成するためのメソッド（再帰的に呼び出される）
sub _to_S_exp {
    my ($this, $indent, $condition, $opt, $call_for_anchor) = @_;

    # 要素数が1かどうか
    my $is_single_node = (!$this->{hasChild} && scalar(@{$this->{terms}}) < 2);
    # 要素数が1の場合インデントを下げない
    my $_indent = ($is_single_node) ? $indent : ($indent . $INDENT_CHAR);


    # S式の作成
    my $S_exp;
    $S_exp = sprintf ("%s(OR\n", $indent) unless ($is_single_node);
    foreach my $term (@{$this->{terms}}) {
	$S_exp .= $term->to_S_exp ($_indent, $condition, $opt, $call_for_anchor);
    }

    # 子要素についてS式を作成
    if ($this->{hasChild}) {
	# 子要素をソートするキー
	my $sortKey = ($this->{condition}{is_phrasal_search} > 0) ? 'pos' : 'gdf';
	my $operationTag = &_getOperationTag ($condition, $call_for_anchor);
	$S_exp .= sprintf ("%s(%s\n", $_indent, $operationTag);
	foreach my $child (sort {$a->{$sortKey} <=> $b->{$sortKey}} @{$this->{children}}) {
	    $S_exp .= $child->to_S_exp(($_indent . $INDENT_CHAR), $condition, $opt, $call_for_anchor);
	}
	$S_exp .= sprintf ("%s)\n", $_indent);
    }
    $S_exp .= "$indent)\n" unless ($is_single_node);

    return $S_exp;
}

# 子要素のまとめかた(AND/OR/PROX/...)を取得
sub _getOperationTag {
    my ($condition, $call_for_anchor) = @_;

    # アンカー検索の場合はOR
    if ($call_for_anchor || $condition->{logical_cond_qkw} eq 'OR') {
	return 'OR';
    }

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
	$child->to_string($space . $INDENT_CHAR);
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



##############################
# プロパティ値の取得用メソッド
##############################

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

sub get_term_type {
    my ($this) = @_;

    if (defined $this->{terms}[0]) {
	return $this->{terms}[0]->get_term_type();
    } else {
	return 10;
    }
}

-1;
