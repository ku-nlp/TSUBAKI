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
use SidRange;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $CONFIG = Configure::get_instance();

sub new {
    my ($class) = @_;

    my $this = {
	did2snippets => {}
    };

    bless $this;
}

sub create_snippets {
    my ($this, $query, $docs, $opt) = @_;

    # 文書IDを標準フォーマットを管理しているホストに割り振る
    my %host2dids = ();
    my $range = new SidRange();
    foreach my $doc (@$docs) {
	if ($CONFIG->{IS_NICT_MODE}) {
	    my $did = $doc->{did};
	    my $host = $range->lookup($did);
	    push(@{$host2dids{$host}}, $doc);
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
	    push(@{$port2docs{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}[$count++ % $num_of_ports]}}, $doc);
	}


	# debug表示用
	if ($opt->{debug}) {
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
	}


	foreach my $port (@{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}}) {
	    next unless (defined $port2docs{$port});

	    my $socket = IO::Socket::INET->new(
		PeerAddr => $CONFIG->{SNIPPET_SERVERS}[$i]{name},
		PeerPort => $port,
		Proto    => 'tcp' );
	
	    $selecter->add($socket) or die "$!\n";
	
	    # 検索クエリの送信
	    print $socket encode_base64(Storable::freeze($query), "") . "\n";
	    print $socket "EOQ\n";

	    # 文書IDの送信
	    print $socket encode_base64(Storable::freeze($port2docs{$port}), "") . "\n";
	    print $socket "EOD\n";

	    # スニペット生成のオプションを送信
	    print $socket encode_base64(Storable::freeze($opt), "") . "\n";
	    print $socket "EOO\n";
	
	    $socket->flush();
	    $num_of_sockets++;
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

	    my $results = Storable::thaw(decode_base64($buff));
	    foreach my $did (keys %$results) {
		$this->{did2snippets}{$did} = $results->{$did};
#		$this->{did2snippets}{$did} = &select_snippets($results->{$did});
	    }
	}
    }
}


sub create_snippets_bak {
    my ($this, $query, $dids, $opt) = @_;

    # 文書IDを標準フォーマットを管理しているホストに割り振る
    my %host2dids = ();
    foreach my $did (@$dids) {
	push(@{$host2dids{$CONFIG->{DID2HOST}{sprintf("%03d", $did / 1000000)}}}, $did);
    }

    my $num_of_sockets = 0;
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@{$CONFIG->{SNIPPET_SERVERS}}); $i++) {
	next unless (exists $host2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{name}});

	# 文書ID列をN分割 (Nは開いているポート数)
	my $num_of_ports = scalar(@{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}});
	my $dids = $host2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{name}};
	my %port2dids = ();
	my $count = 0;

	foreach my $did (@$dids) {
	    push(@{$port2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}[$count++ % $num_of_ports]}}, $did);
	}


	# debug表示用
	if ($opt->{debug}) {
	    print "<HR>all dids=[" if ($opt->{debug});
	    print join(", ", @$dids);
	    print "]<P>\n" if ($opt->{debug});

	    foreach my $port (sort {$a <=> $b} keys %port2dids) {
		print "port=" . $port . "<BR>　dids=[";
		print join(", ", @{$port2dids{$port}});
		print "]<BR>\n";
	    }
	}


	foreach my $port (@{$CONFIG->{SNIPPET_SERVERS}[$i]{ports}}) {
	    next unless (defined $port2dids{$port});

	    my $socket = IO::Socket::INET->new(
		PeerAddr => $CONFIG->{SNIPPET_SERVERS}[$i]{name},
		PeerPort => $port,
		Proto    => 'tcp' );
	
	    $selecter->add($socket) or die;
	
	    # 検索クエリの送信
	    print $socket encode_base64(Storable::freeze($query), "") . "\n";
	    print $socket "EOQ\n";

	    # 文書IDの送信
	    print $socket encode_base64(Storable::freeze($port2dids{$port}), "") . "\n";
	    print $socket "EOD\n";

	    # スニペット生成のオプションを送信
	    print $socket encode_base64(Storable::freeze($opt), "") . "\n";
	    print $socket "EOO\n";
	
	    $socket->flush();
	    $num_of_sockets++;
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

	    my $results = Storable::thaw(decode_base64($buff));
	    foreach my $did (keys %$results) {
		$this->{did2snippets}{$did} = $results->{$did};
#		$this->{did2snippets}{$did} = &select_snippets($results->{$did});
	    }
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

    my %rep2style;
    if ($opt->{highlight}) {
	foreach my $qk (@{$query->{keywords}}) {
	    next if ($qk->{is_phrasal_search} > 0);

	    foreach my $reps (@{$qk->{words}}) {
		foreach my $rep (@$reps) {
		    foreach my $string (split (/\+/, $rep->{string})) {
			$rep2style{$string} = $rep->{stylesheet};
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
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score} || $a->{sid} <=> $b->{sid}} @{$sentences}) {
	    next if (exists($sbuf{$sentence->{rawstring}}));
	    $sbuf{$sentence->{rawstring}} = 1;

	    my $sid = $sentence->{sid};
	    my $length = $sentence->{length};
	    my $num_of_whitespaces = $sentence->{num_of_whitespaces};

	    if ($num_of_whitespaces / $length > 0.2) {
# 		print $num_of_whitespaces . " ";
# 		print $length . " ";
# 		print $sentence->{rawstring} . "<br>\n";
		next;
	    }

	    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		my $highlighted = -1;
		my $surf = $sentence->{surfs}[$i];
		if ($opt->{highlight}) {
		    foreach my $rep (@{$sentence->{reps}[$i]}) {
			if (exists $rep2style{$rep}) {
			    # 代表表記レベルでマッチしたらハイライト

			    $snippets{$sid} .= sprintf qq(<span style="%s">%s</span>), $rep2style{$rep}, $surf;
			    $highlighted = 1;
			}
			last if ($highlighted > 0);
		    }
		}
		# ハイライトされなかった場合 or ハイライトオプションがオフの場合
		$snippets{$sid} .= $surf if ($highlighted < 0);
		$wordcnt++;
		
		# スニペットが N 単語を超えた終了
		if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET}) {
		    $snippets{$sid} .= ($opt->{highlight}) ? " <b>...</b>" : "...";
		    last;
		}
	    }
	    # ★ 多重 foreach の脱出に label をつかう
	    last if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET});
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
	    $snippet .= $snippets{$sid};
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
	$did2snippets{$did} = $snippet;
    }

    return \%did2snippets;
}

1;
