package Tsubaki::TermGroupCreater;

# $Id$

use strict;
use utf8;
use Indexer;
use Configure;
use CDB_File;
use Encode;
use Tsubaki::TermGroup;

my $CONFIG = Configure::get_instance();

sub create {
    my ($result, $option) = @_;

    my @kihonkus = $result->tag;

    my @ids = ();
    foreach my $i (0 .. scalar (@kihonkus) - 1) {
	push (@ids, $i);
    }

    my ($terms, $optionals) = &_create (0, \@kihonkus, \@ids, undef, "", $option);

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

	my $optional_flag = (defined $kihonku && $kihonku->fstring =~ /クエリ不要語/) ? 1 : 0;
	my $term = new Tsubaki::TermGroup (
	    $group_id,
	    undef,
	    \@synnodes,
	    \@tagids,
	    $children,
	    $kihonku,
	    {
		optional_flag => $optional_flag,
		option => $option
	    });

	if ($optional_flag) {
	    $optionals{$term->{text}} = $term unless (defined ($optionals{$term->{text}}));
	} else {
	    unshift (@terms, $term);
	}

	# 係り受けを追加
	my $indexer = new Indexer({ignore_yomi => 1});
	if (defined $kihonku->{parent}) {
	    my $DFDBS_DPND = new CDB_Reader (sprintf ("%s/df.dpnd.cdb.keymap", $CONFIG->{SYNGRAPH_DFDB_PATH}));
	    my $kakarimoto = $indexer->get_repnames2($kihonku);
	    my $kakarisaki = $indexer->get_repnames2($kihonku->{parent});
	    my $optional_flag = ($kihonku->{fstring} =~ /<クエリ必須係り受け>/) ? 0 : 1;
	    foreach my $moto (@$kakarimoto) {
		foreach my $saki (@$kakarisaki) {
		    my $midasi = sprintf ("%s->%s", $moto, $saki);
		    my $gdf = $DFDBS_DPND->get(encode ('utf8', $midasi));

		    my $blockTypes;
		    if ($CONFIG->{USE_OF_BLOCK_TYPES}) {
			$blockTypes = $option->{blockTypes};
		    } else {
			$blockTypes->{""} = 1;
		    }

		    foreach my $tag (keys %{$blockTypes}) {
			my $term = new Tsubaki::Term ({
			    tid => sprintf ("%s-%s", $gid, $count++),
			    text => $midasi,
			    term_type => (($optional_flag) ? 'dpnd' : 'force_dpnd'),
			    gdf => $gdf,
			    blockType => (($tag eq '') ? undef : $tag),
			    node_type => 'basic' });

			if ($optional_flag) {
			    $optionals{$term->get_id()} = $term unless (exists $optionals{$term->get_id()});
			} else {
			    push (@terms, $term);
			}
		    }
		}
	    }
	}

    }

    return (\@terms, \%optionals);
}

1;
