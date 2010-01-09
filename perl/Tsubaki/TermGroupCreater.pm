package Tsubaki::TermGroupCreater;

# $Id$

use strict;
use utf8;
use Indexer;
use Tsubaki::TermGroup;

sub create {
    my ($result) = @_;

    my @kihonkus = $result->tag;

    my @ids = ();
    foreach my $i (0 .. scalar (@kihonkus) - 1) {
	push (@ids, $i);
    }

    my ($terms, $optionals) = &_create (0, \@kihonkus, \@ids, undef, "");
    my $root = new Tsubaki::TermGroup (
	-1,
	undef,
	undef,
	undef,
	$terms,
	undef,
	{
	    isRoot => 1,
	    optionals => $optionals
	});

    return $root;
}

sub _create {
    my ($gid, $kihonkus, $ids, $parent, $space, $option) = @_;

    my @terms;
    my %optionals = ();
    my $count = 0;
    my %visitedKihonkus = ();
    foreach my $k (reverse @$ids) {
	next if (exists $visitedKihonkus{$k});
	my $kihonku = $kihonkus->[$k];

	# もっとも大きいsynnodeを獲得
	my $widest_synnodes;
	foreach my $synnodes ($kihonku->synnodes) {
	    last if ($synnodes == $parent);

	    # synnodeが交差する場合は、交差しなくなるまで子をだどる
	    # 例) 水の中に潜る -> s22145:水中, s10424:中に潜る
	    my $rep = ($synnodes->synnode)[0];
	    my $head = ($rep->tagids)[0];
	    next if ($ids->[0] > $head);

	    $widest_synnodes = $synnodes;
	}
	my @synnodes = $widest_synnodes->synnode;

	my $rep = $synnodes[0];
	my @tagids = $rep->tagids;
	foreach my $tid (@tagids) {
	    $visitedKihonkus{$tid} = 1;
	}


	my $children = undef;
	my $group_id = sprintf ("%s-%s", $gid , $count++);
	if (scalar (@tagids) > 1) {
	    my $_optionals;
	    ($children, $_optionals) = &_create ($group_id, $kihonkus, \@tagids, $widest_synnodes, $space ."\t", $option);
	    foreach my $k (keys %$_optionals) {
		$optionals{$k} = $_optionals->{$k} unless (defined ($optionals{$k}));
	    }
	}

	my $term = new Tsubaki::TermGroup (
	    $group_id,
	    undef,
	    \@synnodes,
	    \@tagids,
	    $children,
	    $kihonku
	    );

	push (@terms, $term);

	# 係り受けを追加
	my $indexer = new Indexer({ignore_yomi => 1});
	if (defined $kihonku->{parent}) {
	    my $kakarimoto = $indexer->get_repnames2($kihonku);
	    my $kakarisaki = $indexer->get_repnames2($kihonku->{parent});
	    my $optional_flag = ($kihonku->{fstring} =~ /<クエリ必須係り受け>/) ? 0 : 1;
	    foreach my $moto (@$kakarimoto) {
		foreach my $saki (@$kakarisaki) {
		    my $term = new Tsubaki::Term ({
			    tid => sprintf ("%s-%s", $gid, $count++),
			    text => sprintf ("%s->%s", $moto, $saki),
			    term_type => 'dpnd',
			    node_type => 'basic' });

		    if ($optional_flag) {
			$optionals{$term->{text}} = $term unless (defined ($optionals{$term->{text}}));
		    } else {
			push (@terms, $term);
		    }
		}
	    }
	}

    }

    return (\@terms, \%optionals);
}

1;
