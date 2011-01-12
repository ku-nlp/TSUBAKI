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
	only_sitesearch => $params->{only_sitesearch},
	qid2rep => $params->{qid2rep},
	qid2qtf => $params->{qid2qtf},
	qid2gid => $params->{qid2gid},
	qid2df => $params->{qid2df},
	gid2qids => $params->{gid2qids},
	dpnd_map => $params->{dpnd_map},
	antonym_and_negation_expansion => $params->{antonym_and_negation_expansion},
	option => $params->{option},
	result => $params->{result},
	s_exp => $params->{s_exp},
	rawstring => $params->{rawstring},
	rep2style => $params->{rep2style},
	synnode2midasi => $params->{synnode2midasi},
	escaped_query => $params->{escaped_query}
    };

    bless $this;
}

sub DESTROY {}

sub normalize {
    my ($this) = @_;

    my @buf;
    foreach my $memberName (sort keys %$this) {
	next if ($memberName =~ /^qid2/);
	next if ($memberName =~ /^gid2/);
	next if ($memberName eq 'only_hitcount');
	next if ($memberName eq 'keywords');
	next if ($memberName eq 'dpnd_map');
	next if ($memberName eq 'start');
	next if ($memberName eq 'score_verbose');
	next if ($memberName eq 'logger');
	next if ($memberName eq 'synnode2midasi');
	next if ($memberName eq 'rep2style');
	next if ($memberName eq 'result');
	next if ($memberName eq 's_exp');
	next if ($memberName eq 'sort_by_year');

	if ($memberName eq 'option') {
	    foreach my $k (sort keys %{$this->{option}}) {
		next if ($k eq 'syngraph_option');
		next if ($k eq 'knp');
		next if ($k eq 'syngraph');
		next if ($k eq 'indexer');
		next if ($k eq 'debug');
		next if ($k eq 'logger');
		next if ($k eq 'URI');
		next if ($k eq 'start');

		my $v = (defined $this->{option}{$k}) ? $this->{option}{$k} : 0;

		if ((ref $v) =~ /(HASH|ARRAY)/) {
		    my @blockT = ();
		    if ($k eq 'blockTypes') {
			while (my ($kk, $vv) = each %$v) {
			    push (@blockT, sprintf ("%s=%s", $kk, $vv));
			}
		    }
		    push(@buf, sprintf ("%s={%s}", $k, join(",", @blockT)));
		} else {
		    push(@buf, $k . '=' . $v);
		}
	    }
	} else {
	    my $v = (defined $this->{$memberName}) ? $this->{$memberName} : 0;
	    push(@buf, $memberName . "=" . $this->{$memberName});
	}
    }

    my $i = 0;
    foreach my $keyword (sort {$a->{rawstring} cmp $b->{rawstring}} @{$this->{keywords}}) {
	push(@buf, "keyword${i}[" . $keyword->normalize() . ']');
	$i++;
    }

    my $normalizedQueryString = join(',', @buf);
    if (utf8::is_utf8($normalizedQueryString)) {
	return $normalizedQueryString;
    } else {
	return decode('utf8', $normalizedQueryString);
    }
}

1;
