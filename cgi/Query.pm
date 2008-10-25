package Query;

# $Id$

# 検索クエリを表すクラス

use strict;
use utf8;
use Configure;

# コンストラクタ
sub new {
    my ($class, $params) = @_;

    my $this = {
	keywords => $params->{keywords},
	logical_cond_qk => $params->{logical_cond_qk},
	only_hitcount => $params->{only_hitcount},
	qid2rep => $params->{qid2rep},
	qid2qtf => $params->{qid2qtf},
	qid2gid => $params->{qid2gid},
	qid2df => $params->{qid2df},
	gid2qids => $params->{gid2qids},
	dpnd_map => $params->{dpnd_map},
	antonym_and_negation_expansion => $params->{antonym_and_negation_expansion},
	option => $params->{option}
    };

    bless $this;
}

sub DESTROY {}

sub normalize {
    my ($this) = @_;

    my @buf;
    foreach my $memberName (keys %$this) {
	next if ($memberName =~ /^qid2/);
	next if ($memberName =~ /^gid2/);
	next if ($memberName eq 'only_hitcount');
	next if ($memberName eq 'keywords');
	next if ($memberName eq 'dpnd_map');
	next if ($memberName eq 'start');
	next if ($memberName eq 'score_verbose');

	if ($memberName eq 'option') {
	    foreach my $k (keys %{$this->{option}}) {
		next if ($k eq 'syngraph_option');
		next if ($k eq 'knp');
		next if ($k eq 'syngraph');
		next if ($k eq 'indexer');
		next if ($k eq 'debug');

		my $v = $this->{option}{$k};

		next if ((ref $v) =~ /HASH|ARRAY/);

		push(@buf, $k . '=' . $v);
	    }
	} else {
	    push(@buf, $memberName . "=" . $this->{$memberName});
	}
    }

    my $i = 0;
    foreach my $keyword (sort {$a->{rawstring} cmp $b->{rawstring}} @{$this->{keywords}}) {
	push(@buf, "keyword${i}[" . $keyword->normalize() . ']');
	$i++;
    }

    return join(',', @buf);
}

1;
