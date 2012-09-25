package SnippetMakerAgent;

# $Id$

use strict;
use Encode;
use utf8;
use Storable;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use QueryParser;
use Configure;
use Data::Dumper;
use Error qw(:try);
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $CONFIG = Configure::get_instance();

sub new {
    my ($class) = @_;

    my $this = {
	did2snippets => {},
	did2region => {}
    };

    bless $this;
}

sub create_snippets {
    my ($this, $query, $docs, $opt) = @_;

    # 文書IDを標準フォーマットを管理しているホストに割り振る
    my %host2dids = ();
    my $range = undef;
    if ($CONFIG->{SID_RANGE} || $CONFIG->{SID_CDB} || $CONFIG->{USE_OF_HASH_FOR_SID_LOOKUP}) {
 	require SidRange;
	$range = new SidRange();
    }

    my $count = 0;
    foreach my $doc (@$docs) {
	if ($CONFIG->{IS_KUHP_MODE}) {
	    push(@{$host2dids{$CONFIG->{KUHP_SNIPPET_SERVERS}[$count++%scalar(@{$CONFIG->{KUHP_SNIPPET_SERVERS}})]}}, $doc);
	}
 	elsif ($range) { # SidRangeを使うとき
 	    my $did = sprintf ("%09d", $doc->{did});
 	    my $host = $range->lookup($did);
 	    push(@{$host2dids{$host}}, $doc);
 	}
	else {
	    push(@{$host2dids{$CONFIG->{DID2HOST}{sprintf("%04d", $doc->{did} / 1000000)}}}, $doc);
	}
    }

    my $num_of_sockets = 0;
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@{$CONFIG->{SNIPPET_SERVERS}}); $i++) {
	next unless (exists $host2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{name}});

	# 文書ID列をN分割 (Nは開いているポート数)
	my $num_of_ports = scalar(@{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}});
	my $dids = $host2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{name}};

	my %port2docs = ();
	my $count = 0;
	foreach my $doc (@$dids) {
	    $this->{did2region}{$doc->{did}}{start} = $doc->{start};
	    $this->{did2region}{$doc->{did}}{end} = $doc->{end};

	    push(@{$port2docs{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}[$count++ % $num_of_ports]}}, $doc);
	}


	# debug表示用
	if ($opt->{debug} > 1) {
	    print $CONFIG->{SNIPPET_SERVERS}[$i]{name} . "<BR>\n";

	    my @dids = ();
	    foreach my $doc (@$docs) {
		push (@dids, $doc->{did});

	    }
	    print "<HR>all dids=[" . join(", ", @dids) . "]<P>\n";

	    foreach my $port (sort {$a <=> $b} keys %port2docs) {
		print "port=" . $port . "<BR>　dids=[";

		my @dids2 = ();
		foreach my $d (@{$port2docs{$port}}) {
		    push (@dids2, $d->{did});
		}
		print join(", ", @dids2);
		print "]<BR>\n";
	    }
	    print Dumper ($opt) . "<BR>\n";
	}


	foreach my $port (@{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}}) {
	    next unless (defined $port2docs{$port});

	    my $socket = IO::Socket::INET->new(
		PeerAddr => $CONFIG->{SNIPPET_SERVERS}[$i]{name},
		PeerPort => $port,
		Proto    => 'tcp' );

	    try {
		$selecter->add($socket) or die "Cannot connect to the server (host=$CONFIG->{SNIPPET_SERVERS}[$i]{name}, port=$port)";

		# 検索クエリの送信
		print $socket encode_base64(Storable::nfreeze($query), "") . "\n";
		print $socket "EOQ\n";

		# 文書IDの送信
		print $socket encode_base64(Storable::nfreeze($port2docs{$port}), "") . "\n";
		print $socket "EOD\n";

		# スニペット生成のオプションを送信
		print $socket encode_base64(Storable::nfreeze($opt), "") . "\n";
		print $socket "EOO\n";

		$socket->flush();
		$num_of_sockets++;
	    } catch Error with {
		# エラーメッセージの出力
 		my $err = shift;
 		print "<FONT color=white>$err->{-text}</FONT>\n";
	    };
	}
    }

    # 検索結果の受信
    my %did2snippets = ();
    my $total_hitcount = 0;
    while ($num_of_sockets > 0) {
	my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef); # ★
	foreach my $socket (@{$readable_sockets}) {
	    my $buff;
	    while (<$socket>) {
		last if ($_ eq "END\n");
		$buff .= $_;
	    }

	    $selecter->remove($socket);
	    $socket->close();
	    $num_of_sockets--;

	    try {
		my $results = Storable::thaw(decode_base64($buff));
		foreach my $did (keys %$results) {
		    $this->{did2snippets}{$did} = $results->{$did};
		}
	    }
	    catch Error with {
		if ($opt->{debug}) {
		    my $err = shift;
		    print "Can't get snippets for socket ($num_of_sockets)<BR>\n";
		    print "Exception at line ",$err->{-line}," in ",$err->{-file},"<BR>\n";
		}
	    };
	}
    }
}

sub makeKWICForAPICall {
    my ($this, $opt) = @_;

    if (defined $opt->{usedSIDs}) {
	while (my ($did, $kwic) = each %{$this->{did2snippets}}) {
	    if (exists $opt->{usedSIDs}{$did}) {
		my @buf;
		foreach my $e (@$kwic) {
		    my $sid = $e->{sid};
		    next unless (exists $opt->{usedSIDs}{$did}{$sid});

		    push(@buf, $e);
		}
		$this->{did2snippets}{$did} = \@buf;
	    }
	}
    }
    return $this->{did2snippets};
}

sub makeKWICForBrowserAccess {
    my ($this, $opt) = @_;

    my @buf;
    while (my ($did, $kwic) = each %{$this->{did2snippets}}) {
	foreach my $e (@$kwic) {
	    $e->{did} = $did;
	    push(@buf, $e);
	}
    }

    my @kwics = ($opt->{sort_by_contextR}) ?
	sort {$a->{contextR} cmp $b->{contextR} || $a->{InvertedContextL} cmp $b->{InvertedContextL}} @buf:
	sort {$a->{InvertedContextL} cmp $b->{InvertedContextL} || $a->{contextR} cmp $b->{contextR}} @buf;

    return \@kwics;
}

sub get_snippets_for_each_did {
    my ($this, $query, $opt) = @_;

    my $rep2style;
    if ($opt->{highlight}) {
	$rep2style = $query->{rep2style};
	foreach my $qk (@{$query->{keywords}}) {
	    next if ($qk->{condition}{is_phrasal_search} > 0);

	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@$reps) {
		    foreach my $string (split (/\+/, $rep->{string})) {
			$rep2style->{$string} = $rep->{stylesheet};
		    }
		}
	    }
	}
    }

    my %did2snippets = ();
    foreach my $did (keys %{$this->{did2snippets}}) {
	my $wordcnt = 0;
	my %snippets = ();
	my $sentences = $this->{did2snippets}{$did};
	unless (defined($sentences)) {
	    printf "this->{did2snippets}{%s} is not found!<br>\n", $did if $opt->{debug};
	    next;
	}

	# スコアの高い順に処理（同点の場合は、sidの若い順）
	my %sbuf = ();

	my $flag_of_drawline = 0;
	next unless (defined $sentences);

	my $rawstring_num = 0;
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score} || $a->{sid} <=> $b->{sid}} @{$sentences}) {
	    next if (exists($sbuf{$sentence->{rawstring}}));
	    $sbuf{$sentence->{rawstring}} = 1;

	    my $sid = $sentence->{sid};
	    $sid =~ s/^\w+(\d+)$/$1/; # 文ID先頭にアルファベット列があれば削除
	    next if (defined $opt->{usedSIDs}{$did} && !exists $opt->{usedSIDs}{$did}{$sid});

	    my $length = $sentence->{length};
	    my $num_of_whitespaces = $sentence->{num_of_whitespaces};

	    next if ($sentence->{number_of_included_query_types} < 1 && $num_of_whitespaces / $length > 0.2);

	    if ($opt->{rawstring}) {
		next if $sentence->{smoothed_score} == 0 || !$sentence->{rawstring};
		push @{$did2snippets{$did}}, $sentence;
		last if ++$rawstring_num >= $opt->{rawstring_max_num};
		next;
	    }

	    # 単語の位置
	    my $start_pos = $sentence->{start_pos};
	    my $end_pos = $sentence->{end_pos};
	    my $flag_of_underline = 0; # ($this->{did2region}{$did}{start} > 50 && $this->{did2region}{$did}{end} - $this->{did2region}{$did}{start} < 50) ? 1 : 0;

	    my $pos = $start_pos;
	    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		my $highlighted = -1;
		my $surf = $sentence->{surfs}[$i];
		if ($CONFIG->{IS_ENGLISH_VERSION}) { # add a white space for English
		    $surf = ' ' . $surf if $surf !~ /^[.,:;]$/
		}

		if ($opt->{highlight}) {
		    foreach my $rep (@{$sentence->{reps}[$i]}) {
			if (exists $rep2style->{lc($rep)}) {
			    # ハイライトされる単語からのみ線を引く
			    if (!$flag_of_drawline && $flag_of_underline && $this->{did2region}{$did}{start} - $pos < 3) {
				$snippets{$sid} .= qq(<SPAN class="matched_region">);
				$flag_of_drawline = 1;
			    }

			    # 代表表記レベルでマッチしたらハイライト
			    if ($opt->{debug}) {
				$snippets{$sid} .= sprintf qq(<span style="%s">%s<SUB>%s</SUB></span>), $rep2style->{lc($rep)}, $surf, $pos;
 			    } else {
 				$snippets{$sid} .= sprintf qq(<span style="%s">%s</span>), $rep2style->{lc($rep)}, $surf;
 			    }
			    $highlighted = 1;

			    # ハイライトされる単語まで線を引く
			    $snippets{$sid} .= "</SPAN>" if ($flag_of_underline && $pos == $this->{did2region}{$did}{end});
			}
			last if ($highlighted > 0);
		    }
		}

		# ハイライトされなかった場合 or ハイライトオプションがオフの場合
		if ($opt->{debug} > 1) {
		    $snippets{$sid} .= sprintf ("$surf<SUB>%s</SUB>", $pos) if ($highlighted < 0);
		} else {
		    $snippets{$sid} .= $surf if ($highlighted < 0);
		}
		print $did . " " . $sid . " " . $flag_of_underline . " " . $this->{did2region}{$did}{start} . " " . $pos . " " . $this->{did2region}{$did}{end} . "<BR>\n" if ($opt->{debug} > 1);

		$wordcnt++;
		$pos++;

		# スニペットが N 単語を超えたら終了（強調表示中の場合は除く）
		if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET} && $this->{did2region}{$did}{end} < $pos) {
		    $snippets{$sid} .= ($opt->{highlight}) ? " <b>...</b>" : "...";
		    last;
		}
	    }

	    if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET}) {
		$snippets{$sid} .= "</SPAN>" if ($this->{did2region}{$did}{end} > $pos);
		last;
	    }
	}

 	my $snippet;
 	my $prev_sid = -1;
	foreach my $sid (sort {$a <=> $b} keys %snippets) {
	    if ($sid - $prev_sid > 1 && $prev_sid > -1) {
		if ($opt->{highlight}) {
		    $snippet .= " <b>...</b> " unless ($snippet =~ /<b>\.\.\.<\/b>$/);
		} else {
		    $snippet .= " ... " unless ($snippet =~ /\.\.\.$/);
		}
	    }
	    if ($CONFIG->{IS_ENGLISH_VERSION} || $snippet =~ /。$/) { # 英語もしくは日本語で句点で終わっているなら、そのままcat
		$snippet .= ($snippets{$sid});
	    } else {
		$snippet .= ("&nbsp;&nbsp;" . $snippets{$sid});
	    }		

	    $prev_sid = $sid;
	}

	# フレーズの強調表示
	if ($opt->{highlight}) {
	    foreach my $qk (@{$query->{keywords}}){
		next if ($qk->{condition}{is_phrasal_search} < 0);
		$snippet =~ s!$qk->{rawstring}!<b>$qk->{rawstring}</b>!g;
	    }
	}

	$snippet =~ s/S\-ID:\d+//g;

	if ($opt->{rawstring}) {
	    next;
	}

	if ($opt->{debug} > 1) {
	    $did2snippets{$did} = $did . " " . $this->{did2region}{$did}{start} . " " . $this->{did2region}{$did}{end} . " " . $snippet;
	} else {
	    $did2snippets{$did} = $snippet;
	}
    }

    return \%did2snippets;
}

1;
