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

-1;
