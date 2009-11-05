package Searcher;

# $Id$

use strict;
use utf8;
use Encode;
use Time::HiRes;
use SearchEngine;
use Configure;
use URI::Escape qw(uri_escape);
use SnippetMakerAgent;
use Error qw(:try);

our $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my($class, $called_from_API, $is_local_search_mode, $opt) = @_;
    my $this;

    $this->{called_from_API} = $called_from_API;
    $this->{is_local_search_mode} = $is_local_search_mode;
    $this->{titledbs} = ();
    $this->{urldbs} = ();

    if ($this->{is_local_search_mode}) {
	require TsubakiEngineFactory;
	my $factory = new TsubakiEngineFactory($opt);
	$this->{tsubaki} = $factory->get_instance();
    }
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
    my ($this, $query, $logger, $opt) = @_;

    ####################################
    # 検索スレーブサーバーへの問い合わせ
    ####################################

    # 時間の測定開始

    $logger->setTimeAs('create_se_obj', '%.3f');

    my ($hitcount, $results, $status);
    if ($this->{is_local_search_mode}) {
	$opt->{flag_of_dpnd_use} = $query->{flag_of_dpnd_use};
	$opt->{flag_of_dist_use} = $query->{flag_of_dist_use};
	$opt->{flag_of_anchor_use} = $query->{flag_of_anchor_use};
	$opt->{DIST} = $query->{DIST};
	$opt->{LOGGER} = $logger;

	push(@$results, $this->{tsubaki}->search($query, $query->{qid2df}, $opt));
	$hitcount = scalar(@$results->[0]);
	$status = 'search';
    } else {
	my $se_obj = new SearchEngine($opt->{syngraph});
	($hitcount, $results, $status) = $se_obj->search($query, $logger, $opt);
    }

    # ヒット件数をロギング
    $logger->setParameterAs('hitcount', $hitcount);

    # 検索時のステータスをロギング
    $logger->setParameterAs('status', $status);


    return ([], 0, $status) if ($hitcount < 1);


    ################################################
    # 検索スレーブサーバから得られた検索結果のマージ
    ################################################

    my $size = ($query->{dids}) ? $hitcount : $opt->{'start'} + $opt->{'results'};
    $size = $hitcount if ($hitcount < $size);


    # 検索サーバから得られた検索結果のマージ
    my ($mg_result, $miss_title, $miss_url, $total_docs) = $this->merge_search_results($results, $size, $opt);
    $size = (scalar(@{$mg_result}) < $size) ? scalar(@{$mg_result}) : $size;

    # マージに要した時間をロギング
    $logger->setTimeAs('merge', '%.3f');

    # DBの参照回数，検索結果生成に要した文書数をロギング
    $logger->setParameterAs('miss_title', $miss_title);
    $logger->setParameterAs('miss_url', $miss_url);
    $logger->setParameterAs('total_docs', $total_docs);


    return ($mg_result, $size, $status);
}

# 検索サーバから得られた検索結果のマージ
sub merge_search_results {
    my ($this, $results, $size, $opt) = @_;

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

	my $page = shift(@{$results->[$max]});
	$page->{title} = decode('utf8', $page->{title}) unless (utf8::is_utf8($page->{title}));
	my $did = ($CONFIG->{IS_NICT_MODE} || $CONFIG->{IS_IPSJ_MODE}) ? $page->{did} : sprintf("%09d", $page->{did});

	unless ($opt->{'filter_simpages'}) {
	    $this->add_list(\@merged_result, $page, $did, \$miss_title, \$miss_url);
	} else {
	    # URL の取得
	    unless ($page->{url}) {
		$page->{url} = $this->get_url($did);
		$miss_url++;
	    }
	    my $url_mod = &get_normalized_url($page->{url});

	    my $p = $url2pos{$url_mod};
	    if (defined $p) {
		$merged_result[$p]->{similar_pages} = [] unless (defined $merged_result[$p]->{similar_pages});
		$prev->{title} = $page->{title};
		$prev->{url} = $page->{url};
		$prev->{score} = $page->{score_total};
		$this->add_list($merged_result[$p]->{similar_pages}, $page, $did, \$miss_title, \$miss_url);
	    } else {
		my $title = '';
		if (defined $prev && $prev->{score} - $page->{score_total} < 0.05) {
		    if ($prev->{title} eq '') {
			$prev->{title} = $this->get_title($prev->{did});
			$miss_title++;
		    }

		    # タイトルの取得
		    if (defined $page->{title} && $page->{title} ne '') {
			$title = $page->{title};
		    } else {
			$title = $this->get_title($did);
			$page->{title} = $title;
			$miss_title++;
		    }

		    # タイトルが等しくスコアが近ければ類似ページと判定
		    if (defined $prev && $prev->{title} eq $title && $prev->{title} ne 'no title.' && $title ne 'no title.') {
			$url2pos{$url_mod} = $pos - 1;
			$prev->{score} = $page->{score_total};

			$merged_result[$pos - 1]->{similar_pages} = [] unless (defined $merged_result[$pos - 1]->{similar_pages});
			$this->add_list($merged_result[$pos - 1]->{similar_pages}, $page, $did, \$miss_title, \$miss_url);
			next;
		    }
		} else {
		    if (defined $page->{title} && $page->{title} ne '') {
			$title = $page->{title};
		    } else {
			$title = $this->get_title($did);
			$miss_title++;
		    }
		}

		$page->{title} = $title;

		$prev->{did} = $did;
		$prev->{title} = $title;
		$prev->{score} = $page->{score_total};
		$this->add_list(\@merged_result, $page, $did, \$miss_title, \$miss_url);

		$url2pos{$url_mod} = $pos++;
	    }
	}
    }

    return (\@merged_result, $miss_title, $miss_url, $total_docs);
}

sub add_list {
    my ($this, $mg_result, $p, $did, $miss_title, $miss_url) = @_;

    unless ($p->{title}) {
#	$p->{title} = $this->get_title($did);
	$$miss_title++;
    }

    unless ($p->{url}) {
#	$p->{url} = $this->get_url($did);
	$$miss_url++;
    }

    $p->{title} = decode('utf8', $p->{title}) unless (utf8::is_utf8($p->{title}));
    $p->{url} = decode('utf8', $p->{url}) unless (utf8::is_utf8($p->{url}));

    push(@$mg_result, $p);
}

sub get_title {
    my ($this, $did) = @_;

   # タイトルの取得
    my $did_prefix = sprintf("%03d", $did / 1000000);
    my $title = decode('utf8', $this->{titledbs}{$did_prefix}->{$did});
    unless (defined($title)) {
	my $titledbfp = "$CONFIG->{TITLE_DB_PATH}/$did_prefix.title.cdb";
	try {
	    tie my %titledb, 'CDB_File', "$titledbfp" or die "$0: can't tie to $titledbfp $!\n";
	    $this->{titledbs}{$did_prefix} = \%titledb;
	    $title = decode('utf8', $titledb{sprintf("%09d", $did)});
	}
	catch Error with {
	    my $err = shift;
	    # print "Can't access title cdb ($titledbfp)<BR>\n";
	    # print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
	};
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
	try {
	    tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
	    $this->{urldbs}{$did_prefix} = \%urldb;
	    $url = $urldb{sprintf("%09d", $did)};
	}
	catch Error with {
	    my $err = shift;
	    # print "Can't access url cdb ($urldbfp)<BR>\n";
	    # print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
	};
    }

    return $url;
}

# URLの正規化
sub get_normalized_url {
    my ($url) = @_;
    my $url_mod = $url;
    $url_mod =~ s/%7E/~/ig;
    $url_mod =~ s!//www\d*\.!//!;
    $url_mod =~ s/\d+/0/g;
    $url_mod =~ s/\/+/\//g;
    $url_mod =~ s/index.html?$//g;

    my ($proto, $host, @dirpaths) = split('/', $url_mod);
    my $dirpath_mod;
    for (my $i = 0; $i < 2; $i++) {
	$dirpath_mod .= "/$dirpaths[$i]";
    }

    return uc("$host/$dirpath_mod");
}

1;
