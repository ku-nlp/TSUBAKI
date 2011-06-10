package Tsubaki::Term;

# $Id$

# 検索表現を構成する単語・句・係り受けを表すクラス

use strict;
use utf8;
use Encode;
use Configure;

my $CONFIG = Configure::get_instance();

our %TYPE2INT; # 1: strict, 2: lenient, 3: optional
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

# 否定、反義語で拡張する
sub expandAntonymAndNegationTerm {
    my ($this, $_buf) = @_;

    # 反義情報の削除
    my $midasi = lc($this->{text});
    $midasi =~ s/<反義語>//;

    my @features;
    # <否定>の付け変え
    if ($midasi =~ /<否定>/) {
	$midasi =~ s/<否定>//;
	push (@features, '');
    } else {
	push (@features, '<反義語><否定>');
    }

    foreach my $feature (@features) {
	push (@$_buf, sprintf ("%s%s", $midasi, $feature));
    }
}

# <上位語>を付けることで下位語を検索可能にする
sub expandHypernymTerm {
    my ($this, $_buf, $opt) = @_;

    # 反義情報の削除
    my $midasi = lc($this->{text});

    # フレーズの場合は付けない
    unless ($midasi =~ /\*$/) {
	$midasi .= '<上位語>';
	unless (exists $opt->{remove_synids}{$midasi}) {
	    push (@$_buf, $midasi);
	}
    }
}

# S式を出力
sub to_S_exp {
    my ($this, $indent, $condition, $opt, $call_for_anchor) = @_;

    # 係り受けタームの場合は<上位語>の付与、否定・反義語による拡張を行わない
    if ($this->{term_type} =~ /dpnd/) {
	my $midasi = lc($this->{text});
	$this->{blockType} =~ s/://;
	my $term_type = $TYPE2INT{$this->{term_type}};
	my $index_type = (($this->{term_type} =~ /word/) ? 0 : 1);
	my $featureBit = $this->{blockTypeFeature};

	# アンカーインデックス用に変更
	if ($call_for_anchor) {
	    $term_type = 3;
	    $index_type += 2;
	    $featureBit = 1;
	}

	return sprintf("%s((%s %d %d %d %d %d))\n",
		       (($this->{term_type} =~ /dpnd/) ? $indent : $indent . $Tsubaki::TermGroup::INDENT_CHAR),
		       $midasi,
		       $term_type,
		       $this->{gdf},
		       (($this->{node_type} eq 'basic')? 1 : 0),
		       $index_type,
		       $featureBit);
    } else {
	return $this->createORNode($indent, $opt, $call_for_anchor);
    }
}

# 拡張されたタームをORでまとめたノードを作成
sub createORNode {
    my ($this, $indent, $opt, $call_for_anchor) = @_;

    my @midasis = ();
    push (@midasis, lc($this->{text}));

    # タームを拡張する
    push (@midasis, @{$this->termExpansion($opt)}) unless $opt->{english}; # 上位語や否定による拡張 (日本語のみ)

    # <上位語>が付与されたターム、否定・反義語で拡張されたタームをORでまとめる
    my $term_str;
    foreach my $_midasi (@midasis) {
	my $term_type = $TYPE2INT{$this->{term_type}};
	my $index_type = (($this->{term_type} =~ /word/) ? 0 : 1);
	my $featureBit = $this->{blockTypeFeature};
	# アンカーインデックス用に変更
	if ($call_for_anchor) {
	    $term_type = 3;
	    $index_type += 2;
	    $featureBit = 1;
	}

	$term_str .= sprintf("%s((%s %d %d %d %d %d))\n",
			     ($indent . $Tsubaki::TermGroup::INDENT_CHAR),
			     $_midasi,
			     $term_type,
			     $this->{gdf},
			     (($this->{node_type} eq 'basic')? 1 : 0),
			     $index_type,
			     $featureBit );
    }
    return sprintf ("%s(OR\n%s%s)\n",
		    $indent,
		    $term_str,
		    $indent);
}

# termを拡張する
sub termExpansion {
    my ($this, $opt) = @_;

    my @buf;
    # <上位語>を付与して下位語を検索可能にする
    $opt->{hypernym_expansion} = 1;
    $this->expandHypernymTerm (\@buf, $opt) if ($opt->{hypernym_expansion});

    # 否定・反義語でタームを拡張する
    $opt->{antonym_and_negation_expansion} = 1;
    # 拡張されるのは最後の基本句のみ
    $this->expandAntonymAndNegationTerm (\@buf) if ($opt->{antonym_and_negation_expansion} && $this->{is_last_kihonku});

    return \@buf;
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

sub to_string {
    my ($this, $indent) = @_;

    foreach my $k (keys %$this) {
	print $indent . "- " . $k . " = " . $this->{$k} . "\n";
    }
}





###############################
# プロパティ値のget/setメソッド
###############################

sub get_id {
    my ($this) = @_;

    return sprintf "%s%s", $this->{blockType}, $this->{text};
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
    return $TYPE2INT{$this->{term_type}};
}

-1;
