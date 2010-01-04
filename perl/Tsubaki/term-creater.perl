#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Configure;
# use Tsubaki::Term;
use Tsubaki::TermGroup;
use Data::Dumper;
use TsubakiEngineFactory;
use QueryAnalyzer;
use Indexer;


my $CONFIG = Configure::get_instance();

push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});

binmode (STDOUT, ':encoding(euc-jp)');
binmode (STDERR, ':encoding(euc-jp)');

&main();

sub main {
    require SynGraph;

    my $SYNGRAPH = new SynGraph($CONFIG->{SYNDB_PATH});
    # my $knpresult = $CONFIG->{KNP}->parse("水の中にもぐってするスポーツ");
    # my $knpresult = $CONFIG->{KNP}->parse("水の中に長時間もぐってするスポーツ");
    # my $knpresult = $CONFIG->{KNP}->parse("人工知能");
    my $knpresult = $CONFIG->{KNP}->parse("京都大学への行き方");
    # my $knpresult = $CONFIG->{KNP}->parse("京都大学");
    $knpresult->set_id(0);
    my $synresult = new KNP::Result($SYNGRAPH->OutputSynFormat($knpresult, $CONFIG->{SYNGRAPH_OPTION}, $CONFIG->{SYNGRAPH_OPTION}));

    # クエリ解析処理

    my $opt;
    $opt->{end_of_sentence_process} = 1;
    $opt->{telic_process} = 1;
    $opt->{CN_process} = 1;
    $opt->{NE_process} = 1;
    $opt->{modifier_of_NE_process} = 1;

    my $analyzer = new Tsubaki::QueryAnalyzer($opt);
    $analyzer->analyze($synresult,
		       {
			   end_of_sentence_process => $opt->{end_of_sentence_process},
			   telic_process => $opt->{telic_process},
			   CN_process => $opt->{CN_process},
			   NE_process => $opt->{NE_process},
			   modifier_of_NE_process => $opt->{modifier_of_NE_process}
		       });

    my @kihonkus = $synresult->tag;

    my @ids = ();
    foreach my $i (0 .. scalar (@kihonkus) - 1) {
	push (@ids, $i);
    }

    my ($terms, $optionals) = &create (0, \@kihonkus, \@ids, undef, "");
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

    print $root->to_S_exp() . "\n";
    exit;

    my $is_single_node = (scalar(@$terms) > 1) ? 0 : 1;
    # for triangle terms
    print "(";
    print "(AND\n" unless ($is_single_node);
    my $_space = ($is_single_node) ? "" : "\t";
    foreach my $term (@$terms) {
	print $term->to_S_exp($_space);
    }
    print ")\n" unless ($is_single_node);
    print ")";
    exit;
}

#     my $IDXDIR = "/data/skeiji/tsubaki-idxs-090610/dat1";
#     my $opt;
#     $opt->{idxdir} = $IDXDIR;
#     $opt->{dlengthdbdir} = $IDXDIR;
#     $opt->{verbose} = 0;
#     $opt->{doc_length_dbs} = "$IDXDIR/007.doc_length.bin";
#     $opt->{weight_dpnd_score} = 1;
#     $opt->{score_verbose} = 0;
#     $opt->{logging_query_score} = 0;
#     $opt->{idxdir4anchor} = $IDXDIR . "a";
#     $opt->{dpnd_on} = 1;
#     $opt->{dist_on} = 1;
#     $opt->{syngraph} = 1;

#     my $factory = new TsubakiEngineFactory($opt);
#     my $tsubaki = $factory->get_instance();

#     # 検索
#     my %docs;
#     &retrieve ($tsubaki, $terms, \%docs);


#     # 近接
# #    $docs{'7695286'}->to_string . "\n";

# #    print scalar(keys %docs) . "\n";
# #    exit;

#     foreach my $did (sort keys %docs) {
# #	$docs{$did}->to_string . "\n";
# 	print $did . "\n";
#     }
# }

# sub retrieve {
#     my ($tsubaki, $termGroupList, $retrievedDocs, $alreadyRetreivedDocs) = @_;

#     # 異なるtermGroupに属すtermに関してはANDをとる
#     # -> 文書頻度の少ないものから
#     # -> 検索された文書の履歴を保持し、絞りこみをおこなう
#     my @ret;
#     my $strict = 0;
#     my %tmp;
#     my $_retrievedDocs = \%tmp;
#     foreach my $termGroup (sort {$a->gdf <=> $b->gdf} @$termGroupList) {
# 	my %docBuf;

# 	# 同じtermGroupに属すtermに関してはORをとる
# 	foreach my $term (@{$termGroup->terms}) {
# 	    my $ldf;
# 	    if ($strict) {
# 		$ldf = $tsubaki->{word_retriever}->strict_retrieve($term, \%docBuf, $_retrievedDocs);
# 	    } else {
# 		$ldf = $tsubaki->{word_retriever}->retrieve($term, \%docBuf);
# 	    }
	    
# 	    print STDERR $term->{text} . " df=" . $ldf . " gdf=" . $termGroup->gdf . "\n";
# 	}

# 	# 子要素(AIに対する人工, 知能)に関して検索
# 	if ($termGroup->hasChild) {
# 	    my %docsOfChildren;
# 	    &retrieve($tsubaki, $termGroup->children, \%docsOfChildren, $_retrievedDocs);

# 	    while (my ($did, $doc) = each %docsOfChildren) {
# 		if (exists $docBuf{$did}) {
# 		    $docBuf{$did} = $docsOfChildren{$did};
# 		} else {
# 		    $docBuf{$did}->merge($docsOfChildren{$did});
# 		}
# 	    }
# 	}

# 	$_retrievedDocs = \%docBuf;


# 	# 以降の検索は文書の絞りこみを行う
# 	$strict = 1;
#     }


#     # 上位のSYNノードの検索結果とマージ
#     # 本当は $retrievedDocs で回した方が良い？
#     while (my ($did, $document) = each %$_retrievedDocs) {
# 	if (exists $retrievedDocs->{$did}) {
# 	    $retrievedDocs->{$did}->merge($_retrievedDocs->{$did});
# 	} else {
# 	    $retrievedDocs->{$did} = $_retrievedDocs->{$did};
# 	}
#     }
# }


# 配列の配列を受け取り OR をとる (配列の配列をマージして単一の配列にする)
sub merge_search_result {
    my ($this, $docs_list, $idx2qid) = @_;

    my $serialized_docs = [];
    my $pos = 0;
    my %did2pos = ();

    for(my $i = 0, my $docs_list_size = scalar(@{$docs_list}); $i < $docs_list_size ; $i++) {
	my $qid = $idx2qid->{$i};
	foreach my $d (@{$docs_list->[$i]}) {
#	    next unless (defined($d)); # 本来なら空はないはず

	    if (exists($did2pos{$d->[0]})) {
		my $j = $did2pos{$d->[0]};
		push(@{$serialized_docs->[$j]->{qid_freq}}, {qid => $qid, fnum => $d->[1], nums => $d->[2], offset => $d->[3], offset_score => $d->[4]});
	    } else {
		$serialized_docs->[$pos] = {did => $d->[0], qid_freq => [{qid => $qid, fnum => $d->[1], nums => $d->[2], offset => $d->[3], offset_score => $d->[4]}]};

		$did2pos{$d->[0]} = $pos++;
	    }
	}
    }
    # ★このソートは無駄★
    # 上の処理でpushする際に適切な位置に挿入できればよい
    @{$serialized_docs} = sort {$a->{did} <=> $b->{did}} @{$serialized_docs};

    if ($this->{verbose}) {
	foreach my $doc (@{$serialized_docs}) {
	    print "did=" . $doc->{did};
	    foreach my $e (@{$doc->{qid_freq}}) {
		print " qid=$e->{qid}";
	    }
	    print "\n";
	}
	print "--------------------\n";
    }

    return $serialized_docs;
}


sub remove_yomi {
    my ($midasi) = @_;

    my @buf;
    foreach my $w (split(/\+/, $midasi)) {
	my ($hyouki, $yomi) = split(/\//, $w);
	# $hyouki .= $1 if ($yomi =~ /([a|v])$/);
	push (@buf, ${hyouki});
    }

    return  join ('+', @buf);
}

sub create {
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
	    ($children, $_optionals) = &create ($group_id, $kihonkus, \@tagids, $widest_synnodes, $space ."\t", $option);
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
