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
    if ($CONFIG->{IS_KUHP_MODE}) {
	# nothing to do;
    }
    elsif ($CONFIG->{IS_NICT_MODE}) {
 	require SidRange;
 	if ($CONFIG->{IS_NTCIR_MODE}) {
 	    $range = new SidRange({sids_for_ntcir => $CONFIG->{SIDS_FOR_NTCIR}});
 	} else {
 	    $range = new SidRange({nict2nii => $CONFIG->{NICT2NII}});
 	}
    }

    my $count = 0;
    foreach my $doc (@$docs) {
	if ($CONFIG->{IS_KUHP_MODE}) {
	    push(@{$host2dids{$CONFIG->{IPSJ_SNIPPET_SERVERS}[$count++%scalar(@{$CONFIG->{IPSJ_SNIPPET_SERVERS}})]}}, $doc);
	}
 	elsif ($CONFIG->{IS_NICT_MODE}) {
 	    my $did = sprintf ("%09d", $doc->{did});
 	    my $host = $range->lookup($did);
 	    push(@{$host2dids{$host}}, $doc);
 	}
	elsif ($CONFIG->{IS_IPSJ_MODE}) {
	    push(@{$host2dids{$CONFIG->{IPSJ_SNIPPET_SERVERS}[$count++%scalar(@{$CONFIG->{IPSJ_SNIPPET_SERVERS}})]}}, $doc);
	} else {
	    push(@{$host2dids{$CONFIG->{DID2HOST}{sprintf("%03d", $doc->{did} / 1000000)}}}, $doc);
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
#	    print $doc->{did} . " " . $doc->{start} . " " . $doc->{end}. "<BR>\n";
	    push(@{$port2docs{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}[$count++ % $num_of_ports]}}, $doc);

#	    print Dumper ($doc) . "<BR>\n";
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



# サーバから受信したスコア付きの文リストからスニペットで使う文だけを選び出す
sub select_snippets {
    my ($sentences) = @_;

    my $wordcnt = 0;
    my @snippets = ();

    # スコアの高い順に処理
    my %sbuf = ();
    foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score}} @{$sentences}) {
	next if (exists($sbuf{$sentence->{rawstring}}));
	$sbuf{$sentence->{rawstring}} = 1;

	my $sid = $sentence->{sid};
	my $length = $sentence->{length};
	my $num_of_whitespaces = $sentence->{num_of_whitespaces};

	next if ($num_of_whitespaces / $length > 0.2);

	$sentence = decode('utf8', $sentence) unless (utf8::is_utf8($sentence));
	push(@snippets, $sentence);
	$wordcnt += scalar(@{$sentence->{reps}});

	# スニペットが N 単語を超えたら終了
	last if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET});
    }

    return \@snippets;
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
	    next if ($qk->{is_phrasal_search} > 0);

	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@$reps) {
		    foreach my $string (split (/\+/, $rep->{string})) {
			# 論文検索モードであれば、領域タグを削除する
#			$string =~ s/^[A-Z][A-Z]:// if ($CONFIG->{USE_OF_BLOCK_TYPES});
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

	# スコアの高い順に処理（同点の場合は、sidの若い順）
	my %sbuf = ();

	my $flag_of_drawline = 0;
	next unless (defined $sentences);
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score} || $a->{sid} <=> $b->{sid}} @{$sentences}) {
	    next if (exists($sbuf{$sentence->{rawstring}}));
	    $sbuf{$sentence->{rawstring}} = 1;

	    my $sid = $sentence->{sid};
	    next if (defined $opt->{usedSIDs}{$did} && !exists $opt->{usedSIDs}{$did}{$sid});

	    my $length = $sentence->{length};
	    my $num_of_whitespaces = $sentence->{num_of_whitespaces};

	    next if ($sentence->{number_of_included_query_types} < 1 && $num_of_whitespaces / $length > 0.2);

	    # 単語の位置
	    my $start_pos = $sentence->{start_pos} + 1;
	    my $end_pos = $sentence->{end_pos};
	    my $flag_of_underline = 0; # ($this->{did2region}{$did}{start} > 50 && $this->{did2region}{$did}{end} - $this->{did2region}{$did}{start} < 50) ? 1 : 0;

	    my $pos = $start_pos;
	    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		my $highlighted = -1;
		my $surf = $sentence->{surfs}[$i];

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
	    if ($snippet =~ /。$/) {
		$snippet .= ($snippets{$sid});
	    } else {
		$snippet .= ("&nbsp;&nbsp;" . $snippets{$sid});
	    }		

	    $prev_sid = $sid;
	}

	# フレーズの強調表示
	if ($opt->{highlight}) {
	    foreach my $qk (@{$query->{keywords}}){
		next if ($qk->{is_phrasal_search} < 0);
		$snippet =~ s!$qk->{rawstring}!<b>$qk->{rawstring}</b>!g;
	    }
	}

	$snippet =~ s/S\-ID:\d+//g;
	if ($opt->{debug} > 1) {
	    $did2snippets{$did} = $did . " " . $this->{did2region}{$did}{start} . " " . $this->{did2region}{$did}{end} . " " . $snippet;
	} else {
	    $did2snippets{$did} = $snippet;
	}
    }

    return \%did2snippets;
}

1;
