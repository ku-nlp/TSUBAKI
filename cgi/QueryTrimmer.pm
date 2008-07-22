package QueryTrimmer;

use lib '/home/skeiji/cvs/CalcSimilarityByCF/perl';

use strict;
use utf8;
use Encode;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;
# use CalcSimilarityByCF;


sub new {
    my ($clazz, $option) = @_;
    my $this = {
	option => $option
    };

    bless $this;
}

sub trim {
    my ($this, $result) = @_;

    $this->set_bunmatsu_feature($result);

    my @bnst = $result->bnst;
    $this->set_lexical_head_feature($bnst[-1]);

    $this->set_compound_noun_feature($result);
    $this->set_pseudo_NE_feature($result);
    $this->set_single_adjective_feature($result);
    $this->set_discard_feature_by_POS($result);
    $this->set_discard_feature_by_stopword($result);
    $this->set_discard_feature_by_KANJI($result);

    my $option = { debug => 0, usewordsimcache => 1, method => 'SimpsonJaccard' };
    my $cscf; # = new CalcSimilarityByCF($option);
    # $cscf->TieMIDBfile("/home/skeiji/cvs/CalcSimilarityByCF/db/all-mi");

    my @kihonku = $result->tag;
#   $this->set_discard_feature_by_TELIC($kihonku[-1], undef, $cscf, $option, 0.3, {verbose => 0});

    my @bnst = $result->bnst;
    $this->set_modifier_of_NE_feature($bnst[-1], 0);
}

sub set_compound_noun_feature {
    my ($this, $result) = @_;

    my $previous_mrph_is_CN = 0;
    foreach my $mrph (reverse $result->mrph) {
	if ($mrph->fstring =~ /<複合←>/) {
	    $previous_mrph_is_CN = 1;
	} else {
	    if ($previous_mrph_is_CN > 0) {
		my @f = ();
		push(@f, "複合→");
		$mrph->push_feature(@f);
	    }
	    $previous_mrph_is_CN = -1;
	}
    }
}

sub set_discard_feature_by_POS {
    my ($this, $result) = @_;

    foreach my $mrph ($result->mrph) {
	my $hinsi = $mrph->hinsi;
	my $bunrui = $mrph->bunrui;

	if ($hinsi eq '指示詞') {
	    my @f = ();
	    push(@f, "削除::品詞");
	    $mrph->push_feature(@f);
	} 
 	elsif ($hinsi eq '動詞') {
 	    my @f = ();
 	    push(@f, "削除::動詞");
 	    $mrph->push_feature(@f);
 	}
	elsif ($hinsi eq '名詞' && $bunrui eq '形式名詞') {
	    my @f = ();
	    push(@f, "削除::品詞");
	    $mrph->push_feature(@f);
	}
    }
}

sub set_discard_feature_by_KANJI {
    my ($this, $result) = @_;

    foreach my $mrph ($result->mrph) {
	if ($mrph->fstring =~ /<一文字漢字>/) {
	    next if ($mrph->fstring =~ /<NE:/ ||
		     $mrph->fstring =~ /<クエリ主辞>/);
	    my @f = ();
	    push(@f, "削除::漢字");
	    $mrph->push_feature(@f);
	}
    }
}


sub init {


#     my $option = { debug => $opt{debug}, usewordsimcache => 1, method => 'SimpsonJaccard' };
#     $option->{no_frequent_predicate} = 1 if $opt{no_frequent_predicate};
#     $option->{wpccache} = 1 if $opt{wpccache};
#     $option->{print_cooccurence_predicate} = 1 if $opt{print_cooccurence_predicate};
#     $option->{pre_calculate_similarity_th} = $opt{pre_calculate_similarity_th} if $opt{pre_calculate_similarity_th};

}

sub calculate_word_sim {
    my ($word0, $word1, $cscf, $opt) = @_;

    # Hindle
    if ($opt->{calcmethod} eq 'Hindle') {
        my $calcsim_option = { method => $opt->{calcmethod} };
        print $cscf->CalcSimilarity($word0, $word1, $calcsim_option), "\n";
    }
    else {
        # Simpson係数 or Jaccard係数 or SimpsonJaccard
        # 相互情報量がプラスのものだけを対象にする場合、mifilterを指定する
        my $calcsim_option = { method => $opt->{calcmethod}, mifilter => 1, print_pc_freq => 1 };
        print $cscf->CalcSimilarity($word0, $word1, $calcsim_option), "\n";
    }
}

sub get_mi_rank {
    my ($this, $calcCF, $noun, $verb, $joshi, $opt) = @_;

    my $string = $calcCF->GetValue($calcCF->{mi}{$noun});
    if (defined $string) {
	$joshi = undef if ($joshi eq '連');
	my %data;
	foreach my $ex (split (/\|/, $string)) {
	    # 育つ/そだつ:動:ガ;2.768
	    my ($key,$value) = split(/\;/, $ex);
	    my ($verbs, $etc) = ($key =~ /^(.+?):(.+)$/);
	    foreach my $v (split(/\?/, $verbs)) {
		$data{"$v:$etc"} = $value;
		# $data{$key} = $value;
	    }
	}

	my $num = scalar(keys %data);
	my $rank = 1;
	my $r = -1;
	if (defined $joshi) {
	    foreach my $key (sort { $data{$b} <=> $data{$a} } keys %data) {
		printf "%5d %s %s\t%s\n", $rank, $noun, $key, $data{$key} if ($opt->{verbose});
		if ($key =~ /^$verb:.*:$joshi$/) {
		    $r = $rank if ($r < 0);
#		    print "★ " if ($opt->{verbose});
		    last;
		}
		$rank++;
	    }
	} else {
	    foreach my $key (sort { $data{$b} <=> $data{$a} } keys %data) {
		printf "%5d %s %s\t%s\n", $rank, $noun, $key, $data{$key} if ($opt->{verbose});
		if ($key =~ /^$verb:.*:.*$/) {
		    $r = $rank if ($r < 0);
#		    print "★ " if ($opt->{verbose});
		    last;
		}
		$rank++;
	    }
	}
	print "($r / $num)\n" if ($opt->{verbose});
	print "-----\n" if ($opt->{verbose});
	return $r / $num;
    } else {
	return -1;
    }
}

sub set_discard_feature_by_TELIC {
    my ($this, $kihonku, $parent, $calcCF, $option, $th, $opt) = @_;

    my @children = $kihonku->child;
    foreach my $mrph ($kihonku->mrph) {
	if ($mrph->hinsi eq '動詞' && $mrph->fstring =~ /<内容語|意味有>/) {
	    my $kakari_saki;
	    my $kakari_moto;
#	    my ($repname) = ($mrph->fstring =~ /<正規化代表表記.?:([^>]+)>/);
	    my $repname = $mrph->repname;
	    if (defined $parent) {
		($kakari_saki) = ($parent->fstring =~ /<正規化代表表記.?:([^>]+)>/);
		print "$repname $kakari_saki\n";
		my ($joshi) = ($kihonku->fstring =~ /<係:(.+?)格>/);

		my $score = $this->get_mi_rank($calcCF, $kakari_saki, $repname, $joshi, {verbose => $opt->{verbose}});
		if ($opt->{verbose}) {
		    print "=====\n";
		    print $repname . " " . $kakari_saki . " " . $joshi . " $score\n";
		    print "=====\n";
		}

		if (0 < $score && $score <= $th) {
		    my @f = ();
		    $score = sprintf("%0.3f", $score);
		    push(@f, "削除::相互情報量（$kakari_saki, $score）");
		    $mrph->push_feature(@f);
		}
	    }

	    foreach my $c (@children) {
		($kakari_moto) = ($c->fstring =~ /<正規化代表表記.?:([^>]+)>/);
		my ($joshi) = ($c->fstring =~ /<係:(.+?)格>/);
		print "$kakari_moto $repname\n";

		my $score = $this->get_mi_rank($calcCF, $kakari_moto, $repname, $joshi, {verbose => $opt->{verbose}});
		if ($opt->{verbose}) {
		    print "=====\n";
		    print $kakari_moto . " " . $repname . " " . $joshi . " $score\n";
		    print "=====\n";
		}

		if (0 < $score && $score <= $th) {
		    my @f = ();
		    $score = sprintf("%0.3f", $score);
		    push(@f, "削除::相互情報量（$kakari_moto, $score）");
		    $mrph->push_feature(@f);
		}
	    }
	}
    }

    if (defined @children) {
	foreach my $c (@children) {
	    $this->set_discard_feature_by_TELIC($c, $kihonku, $calcCF, $option, $th, $opt);
	}
    }
}

sub set_discard_feature_by_stopword {
    my ($this, $result) = @_;

    foreach my $mrph ($result->mrph) {
	if ($mrph->fstring =~ /代表表記:有る\/ある/ ||
	    $mrph->fstring =~ /代表表記:言う\/いう/ ||
	    $mrph->fstring =~ /代表表記:呼ぶ\/よぶ/ ||
	    $mrph->fstring =~ /代表表記:有る\/ある/ ||
	    $mrph->fstring =~ /代表表記:見る\/みる/ ||
	    $mrph->fstring =~ /代表表記:何\/なん/ ||
	    $mrph->fstring =~ /代表表記:書く\/かく/ ||
	    $mrph->fstring =~ /代表表記:書く\/かく/ ||
	    $mrph->fstring =~ /代表表記:関心\/かんしん/ ||
	    $mrph->fstring =~ /代表表記:関連\/かんれん/ ||
	    $mrph->fstring =~ /代表表記:関係\/かんけい/ ||
	    $mrph->fstring =~ /代表表記:関する\/かんする/) {
	    my @f = ();
	    push(@f, "削除::不要語");
	    $mrph->push_feature(@f);
	}
    }
}

sub set_bunmatsu_feature {
    my ($this, $result) = @_;

    # 文末表現削除素性の追加
    foreach my $bnst (reverse $result->bnst) {
	my $all_mrph_matched = 1;
	foreach my $tag (reverse $bnst->tag) {
	    next unless ($tag->fstring =~ /<クエリ削除語>/);

	    foreach my $mrph ($tag->mrph) {
		my @f = ();
		push(@f, "削除::表現文末");
		$mrph->push_feature(@f);
	    }
	}
    }
}


# 主辞の設定
sub set_lexical_head_feature {
    my ($this, $b) = @_;

    if ($b->fstring =~ /削除::全て表現文末/) {
	my @children = $b->child;
# 	foreach my $c ($b->child) {
# 	    $this->set_lexical_head_feature($c);
# 	}
	if (@children) {
	    $this->set_lexical_head_feature($children[-1]);
	}
    } else {
	foreach my $mrph ($b->mrph) {
	    next if ($mrph->fstring =~ /<削除::表現文末>/);
	    next if ($mrph->hinsi ne '名詞' && $mrph->hinsi ne '未定義語');
	    next if ($mrph->bunrui eq '形式名詞' || $mrph->bunrui eq '数詞');

	    my @f = ();
	    push(@f, "クエリ主辞");
	    $mrph->push_feature(@f);
	}

	foreach my $c ($b->child) {
	    if ($c->dpndtype eq 'P') {
		$this->set_lexical_head_feature($c);
	    }
	}
    }
}

sub set_pseudo_NE_feature {
    my ($this, $result) = @_;

    my $kakko_flag = -1;
    # 疑似NEの設定
    foreach my $mrph ($result->mrph) {
	if ($mrph->fstring =~ /<未知語>/ && $mrph->fstring =~ /<カタカナ>/) {
	    my @f = ();
	    push(@f, "NE:疑似");
	    $mrph->push_feature(@f);
	}
	elsif ($mrph->midasi =~ /「|『/) {
	    $kakko_flag = 1;
	}
	elsif ($mrph->midasi =~ /」|』/) {
	    $kakko_flag = -1;
	}
	else {
	    if ($kakko_flag > 0) {
		my @f = ();
		push(@f, "NE:疑似");
		$mrph->push_feature(@f);
	    }
	}
    }
}

sub set_single_adjective_feature {
    my ($this, $result) = @_;

    # 単独形容詞・形容動詞の検出
    foreach my $bnst ($result->bnst) {
	my @mrphs = $bnst->mrph;

	my $size = scalar(@mrphs);
	my $hinsi = $mrphs[0]->hinsi;
	unless (defined $mrphs[1]) {
	    if ($hinsi eq '形容詞' || $hinsi eq '形容動詞') {
		my @f = ();
		push(@f, "${hinsi}単独");
		$mrphs[0]->push_feature(@f);
	    }
	}
	else {
	    if (($hinsi eq '形容詞' || $hinsi eq '形容動詞') &&
		$mrphs[1]->fstring !~ /<複合←>/) {
		my @f = ();
		push(@f, "${hinsi}単独");
		$mrphs[0]->push_feature(@f);
	    }

	    for (my $i = 1; $i < $size; $i++) {
		my $hinsi = $mrphs[$i]->hinsi;
		if (($hinsi eq '形容詞' || $hinsi eq '形容動詞') &&
		    $mrphs[$i]->fstring !~ /<複合←>/) {
		    my @f = ();
		    push(@f, "${hinsi}単独");
		    $mrphs[$i]->push_feature(@f);
		}
	    }
	}
    }
}

sub set_modifier_of_NE_feature {
    my ($this, $bnst, $NE_found) = @_;

    foreach my $mrph (reverse $bnst->mrph) {
	if ($NE_found) {
	    unless ($mrph->fstring =~ /<NE:/) {
		my @f = ();
		push(@f, "NE修飾");
		$mrph->push_feature(@f);
	    } else {
		if ($mrph->fstring =~ /代表表記:日本\/にほん/) {
		    my @f = ();
		    push(@f, "NE修飾");
		    $mrph->push_feature(@f);
		}
	    }
	} else {
	    if ($mrph->fstring =~ /<NE/) {
		$NE_found = 1;
	    }
	}
    }

    foreach my $child ($bnst->child) {
	$this->set_modifier_of_NE_feature($child, $NE_found);
    }
}
1;
