package SearchEngine;

use strict;
use utf8;
use Encode;
use Time::HiRes;
use Configure;

our $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my($class, $called_from_API) = @_;
    my $this;

    $this->{called_from_API} = $called_from_API;
    $this->{titledbs} = ();
    $this->{urldbs} = ();

    bless $this;
}

# デストラクタ
sub DESTROY {
    my ($this) = @_;

    # DB の untie
    foreach my $k (keys %{$this->{titledbs}}){
	untie %{$this->{titledbs}{$k}};
    }
    foreach my $k (keys %{$this->{urldbs}}){
	untie %{$this->{urldbs}{$k}};
    }
}

sub search {
    my ($query, $items4log, $opt) = @_;

    # 検索
    my $se_obj = new SearchEngine($opt->{syngraph});
    my $start_time = Time::HiRes::time;
    my ($hitcount, $results) = $se_obj->search($query);
    $items4log->{hitcount} = $hitcount;
    $items4log->{search_time} = Time::HiRes::time - $start_time; # 検索に要した時間を取得

    return (0, undef) if ($hitcount < 1);

    my $size = $opt->{'start'} + $opt->{'results'};
    $size = $hitcount if ($hitcount < $size);
    $opt->{'results'} = $hitcount if ($opt->{'results'} > $hitcount);

    # 検索サーバから得られた検索結果のマージ
    my ($mg_result, $miss_title, $miss_url, $total_docs) = &merge_search_results($results, $size, $opt);
    $size = (scalar(@{$mg_result}) < $size) ? scalar(@{$mg_result}) : $size;

    $items4log->{miss_title} = $miss_title;
    $items4log->{miss_url} = $miss_url;
    $items4log->{total_docs} = $total_docs;

    if ($opt->{snippet}) {
	# 検索結果（表示分）についてスニペットを生成
	&print_search_result($opt, $mg_result, $query, $opt->{'start'}, $size, $hitcount);
    }

    return ($hitcount, $mg_result);
}

# 検索サーバから得られた検索結果のマージ
sub merge_search_results {
    my ($results, $size, $opt) = @_;

    my $num_of_merged_docs = 0;
    my @merged_result;
    my $pos = 0;
    my %url2pos = ();
    my $prev = undef;
    my $miss_title = 0;
    my $miss_url = 0;
    my $total_docs = 0;

    while (scalar(@merged_result) < $size) {
	$total_docs++;
	my $max = -1;
	my $flag = 0;

	if ($opt->{sort_by} eq 'random') {
	    my @buf = ();
	    for (my $i = 0; $i < scalar(@{$results}); $i++) {
		next if (scalar(@{$results->[$i]}) < 1 ||
			 $results->[$i][0]{score_total} eq '');
		$flag = 1;

		push(@buf, $i);
	    }

	    if ($flag > 0) {
		my $size = scalar(@buf);
		$max = int($size * rand());
	    }
	} else {
	    for (my $i = 0; $i < scalar(@{$results}); $i++) {
		next if (scalar(@{$results->[$i]}) < 1 ||
			 $results->[$i][0]{score_total} eq '');
		$flag = 1;

		if ($max < 0) {
		    $max = $i;
		} elsif ($results->[$max][0]{score_total} < $results->[$i][0]{score_total}) {
		    $max = $i;
		} elsif ($results->[$max][0]{score_total} == $results->[$i][0]{score_total}) {
		    $max = $i if ($results->[$max][0]{did} < $results->[$i][0]{did});
		}
	    }
	}
	last if ($flag < 1);

	my $did = sprintf("%09d", $results->[$max][0]{did});

	unless ($opt->{'filter_simpages'}) {
	    push (@merged_result, shift(@{$results->[$max]}));
	} else {
	    # URL の取得
	    my $url;
	    if ($results->[$max][0]{url}) {
		$url = $results->[$max][0]{url};
	    } else {
		$url = &get_url($did);
		$results->[$max][0]{url} = $url;
		$miss_url++;
	    }
	    my $url_mod = &get_normalized_url($url);

	    my $p = $url2pos{$url_mod};
	    if (defined $p) {
		push(@{$merged_result[$p]->{similar_pages}}, shift(@{$results->[$max]}));
	    } else {
		my $title = '';
		if ($prev->{score} - $results->[$max][0]{score_total} < 0.05) {
		    if ($prev->{title} eq '') {
			$prev->{title} = &get_title($prev->{did});
			$miss_title++;
		    }
		    # タイトルの取得
		    if ($results->[$max][0]{title}) {
			$title = $results->[$max][0]{title};
		    } else {
			$title = &get_title($did);
			$results->[$max][0]{title} = $title;
			$miss_title++;
		    }

		    # タイトルが等しくスコアが近ければ類似ページと判定
		    if (defined $prev && $prev->{title} eq $title) {# && $title ne 'no title.') {
			$url2pos{$url_mod} = $pos - 1;
			$prev->{score} = $results->[$max][0]{score_total};
			push(@{$merged_result[$pos - 1]->{similar_pages}}, shift(@{$results->[$max]}));
			next;
		    }
		} else {
		    $title = $results->[$max][0]{title} if ($results->[$max][0]{title});
		}

		$results->[$max][0]{title} = $title;

		$prev->{did} = $did;
		$prev->{title} = $title;
		$prev->{score} = $results->[$max][0]{score_total};
		$merged_result[$pos] = shift(@{$results->[$max]});
		$url2pos{$url_mod} = $pos++;
	    }
	}
    }

    return (\@merged_result, $miss_title, $miss_url, $total_docs);
}

sub get_snippets {
    my ($this, $opt, $result, $query, $from, $end, $hitcount) = @_;

    # キャッシュページで索引語をハイライトさせるため、索引語をuri_escapeした文字列を生成する
    my $search_k;
    foreach my $qk (@{$query->{keywords}}) {
	my $words = $qk->{words};
	foreach my $reps (sort {$a->[0]{pos} <=> $b->[0]{pos}} @$words) {
	    foreach my $rep (sort {$b->{string} cmp $a->{string}} @$reps) {
		next if ($rep->{isContentWord} < 1 && $rep->{is_phrasal_search} < 1);
		my $string = $rep->{string};

		$string =~ s/s\d+://; # SynID の削除
		$string =~ s/\/.+$//; # 読みがなの削除
		$search_k .= "$string:";
	    }
	}
    }
    chop($search_k);
    my $uri_escaped_search_keys = &uri_escape(encode('utf8', $search_k));

    # スニペット生成のため、類似ページも含め、表示されるページのIDを取得
    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	push(@{$query->{dids}}, $did);

	unless ($this->{called_from_API}) {
	    foreach my $sim_page (@{$result->[$rank]{similar_pages}}) {
		my $did = sprintf("%09d", $sim_page->{did});
		push(@{$query->{dids}}, $did);
	    }
	}
    }

    my $sni_obj = new SnippetMakerAgent();
    $sni_obj->create_snippets($query, $query->{dids}, {discard_title => 1, syngraph => $opt->{'syngraph'}, window_size => 5});
    # 装飾されたスニペッツを取得
    my $did2snippets = ($this->{called_from_API}) ? $sni_obj->get_snippets_for_each_did($query) : $sni_obj->get_decorated_snippets_for_each_did($query, $query->{color});
    for (my $rank = $from; $rank < $end; $rank++) {
	my $did = sprintf("%09d", $result->[$rank]{did});
	$result->[$rank]{snippet} = $did2snippets->{$did};
    }
    $this->{snippet_maker} = $sni_obj;
}


sub get_title {
    my ($this, $did) = @_;

    # タイトルの取得
    my $did_prefix = sprintf("%03d", $did / 1000000);
    my $title = $this->{titledbs}{$did_prefix}->{$did};
    unless (defined($title)) {
	my $titledbfp = "$CONFIG->{TITLE_DB_PATH}/$did_prefix.title.cdb";
	tie my %titledb, 'CDB_File', "$titledbfp" or die "$0: can't tie to $titledbfp $!\n";
	$this->{titledbs}{$did_prefix} = \%titledb;
	$title = $titledb{$did};
    }

    if ($title eq '') {
	return 'no title.';
    } else {
	# 長い場合は省略
	if (length($title) > $CONFIG->{MAX_LENGTH_OF_TITLE}) {
	    $title =~ s/(.{$CONFIG->{MAX_LENGTH_OF_TITLE}}).*/\1 <B>\.\.\.<\/B>/
	}
	return $title;
    }
}

sub get_url {
    my ($this, $did) = @_;

    # URL の取得
    my $did_prefix = sprintf("%03d", $did / 1000000);
    my $url = $this->{urldbs}{$did_prefix}->{$did};
    unless (defined($url)) {
	my $urldbfp = "$CONFIG->{URL_DB_PATH}/$did_prefix.url.cdb";
	tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
	$this->{urldbs}{$did_prefix} = \%urldb;
	$url = $urldb{$did};
    }

    return $url;
}

# URLの正規化
sub get_normalized_url {
    my ($url) = @_;
    my $url_mod = $url;
    $url_mod =~ s/\d+/0/g;
    $url_mod =~ s/\/+/\//g;

    my ($proto, $host, @dirpaths) = split('/', $url_mod);
    my $dirpath_mod;
    for (my $i = 0; $i < 2; $i++) {
	$dirpath_mod .= "/$dirpaths[$i]";
    }

    return uc("$host/$dirpath_mod");
}

1;
