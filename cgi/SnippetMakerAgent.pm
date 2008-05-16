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
	query_parser => undef
    };

    $this->{query_parser} = new QueryParser({
	KNP_COMMAND => $CONFIG->{KNP_COMMAND},
	JUMAN_COMMAND => $CONFIG->{JUMAN_COMMAND},
	SYNDB_PATH => $CONFIG->{SYNDB_PATH},
	KNP_OPTIONS => $CONFIG->{KNP_OPTIONS} });
    
    bless $this;
}

sub create_snippets {
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

	my $socket = IO::Socket::INET->new(
	    PeerAddr => $CONFIG->{SNIPPET_SERVERS}[$i]{name},
	    PeerPort => $CONFIG->{SNIPPET_SERVERS}[$i]{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die;
	
 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";

 	# 文書IDの送信
 	print $socket encode_base64(Storable::freeze($host2dids{$CONFIG->{SNIPPET_SERVERS}[$i]{name}}), "") . "\n";
	print $socket "EOD\n";

	# スニペット生成のオプションを送信
 	print $socket encode_base64(Storable::freeze($opt), "") . "\n";
	print $socket "EOO\n";
	
	$socket->flush();
	$num_of_sockets++;
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

sub get_kwic_snippets_for_each_did {
    my ($this, $query, $opt) = @_;

    my %did2snippets = ();
    foreach my $did (keys %{$this->{did2snippets}}) {
	my $sentences = $this->{did2snippets}{$did};

	# スコアの高い順に処理
	my %sbuf = ();
	my $snippet;
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score}} @{$sentences}) {
	    next if (exists($sbuf{$sentence->{rawstring}}));
	    $sbuf{$sentence->{rawstring}} = 1;

	    my $sid = $sentence->{sid};
	    my $keyword = $query->{keywords}[0]{rawstring};
	    my $length = length($keyword);
	    my $size = scalar(@{$query->{keywords}[0]{words}});

 	    my $start = $sentence->{startOfKeyword};
 	    my $end = $sentence->{endOfKeyword};

 	    my $fwd;
 	    my $bck;
	    my $kwd;
#  	    for (my $i = 0; $i < $start; $i++) {
#  		$fwd .= $sentence->{surfs}[$i];
#  	    }
#  	    for (my $i = $end + 1; $i < scalar(@{$sentence->{surfs}}); $i++) {
#  		$bck .= $sentence->{surfs}[$i];
#  	    }
#  	    for (my $i = $start; $i < $end + 1; $i++) {
#  		$kwd .= $sentence->{surfs}[$i];
#  	    }

# 	    $fwd = substr($fwd, (length($fwd) - $opt->{kwic_window_size} > 0) ? length($fwd) - $opt->{kwic_window_size} : 0);
# 	    $bck = substr($bck, 0, $opt->{kwic_window_size});

	    
	    $kwd = $keyword;
	    if ($sentence->{rawstring} =~ /$keyword/) {
		$fwd = "$`";
		$bck = "$'";
		$fwd = substr($fwd, (length($fwd) - $opt->{kwic_window_size} > 0) ? length($fwd) - $opt->{kwic_window_size} : 0);
		$bck = substr($bck, 0, $opt->{kwic_window_size});
		$snippet .= qq(<TD style="text-align: right; width: $opt->{kwic_window_size}em;" nowrap>$fwd</TD><TD style="width: ${length}em;" nowrap><SPAN style="background-color:yellow; font-weight: bold:">$kwd</SPAN></TD><TD style="text-align: left; width: $opt->{kwic_window_size}em;" nowrap>$bck</TD>\t);
	    }
	}
	$snippet =~ s/S\-ID:\d+//g;
	$did2snippets{$did} = $snippet;
    }

    return \%did2snippets;
}

sub get_snippets_for_each_did {
    my ($this) = @_;

    my %did2snippets = ();
    foreach my $did (keys %{$this->{did2snippets}}) {
	my $wordcnt = 0;
	my %snippets = ();
	my $sentences = $this->{did2snippets}{$did};

	# スコアの高い順に処理
	my %sbuf = ();
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score}} @{$sentences}) {
	    next if (exists($sbuf{$sentence->{rawstring}}));
	    $sbuf{$sentence->{rawstring}} = 1;

	    my $sid = $sentence->{sid};
	    my $length = $sentence->{length};
	    my $num_of_whitespaces = $sentence->{num_of_whitespaces};

	    next if ($num_of_whitespaces / $length > 0.2);

	    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		$snippets{$sid} .= $sentence->{surfs}[$i];
		$wordcnt++;
		
		# スニペットが N 単語を超えた終了
		if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET}) {
		    $snippets{$sid} .= " ...";
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
		$snippet .= " ... " unless ($snippet =~ /\.\.\.$/);
	    }
	    $snippet .= $snippets{$sid};
	    $prev_sid = $sid;
	}

	$snippet =~ s/S\-ID:\d+//g;
	$did2snippets{$did} = $snippet;
    }

    return \%did2snippets;
}

sub get_decorated_snippets_for_each_did {
    my ($this, $query, $color) = @_;

    my %did2snippets = ();
    foreach my $did (keys %{$this->{did2snippets}}) {
	my $wordcnt = 0;
	my %snippets = ();
	my $sentences = $this->{did2snippets}{$did};

	# スコアの高い順に処理
	my %sbuf = ();
	foreach my $sentence (sort {$b->{smoothed_score} <=> $a->{smoothed_score}} @{$sentences}) {
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
		foreach my $rep (@{$sentence->{reps}[$i]}) {
		    if (exists($color->{$rep})) {
			# 代表表記レベルでマッチしたらハイライト

			$snippets{$sid} .= sprintf("<span style=\"color:%s;margin:0.1em 0.25em;background-color:%s;\">%s<\/span>", $color->{$rep}->{foreground}, $color->{$rep}->{background}, $surf);
			$highlighted = 1;
		    }
		    last if ($highlighted > 0);
		}
		# ハイライトされなかった場合
		$snippets{$sid} .= $surf if ($highlighted < 0);
		$wordcnt++;
		
		# スニペットが N 単語を超えた終了
		if ($wordcnt > $CONFIG->{MAX_NUM_OF_WORDS_IN_SNIPPET}) {
		    $snippets{$sid} .= " <b>...</b>";
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
		$snippet .= " <b>...</b> " unless ($snippet =~ /<b>\.\.\.<\/b>$/);
	    }
	    $snippet .= $snippets{$sid};
	    $prev_sid = $sid;
	}
	
	# フレーズの強調表示
	foreach my $qk (@{$query->{keywords}}){
	    next if ($qk->{is_phrasal_search} < 0);
	    $snippet =~ s!$qk->{rawstring}!<b>$qk->{rawstring}</b>!g;
	}
	
	$snippet =~ s/S\-ID:\d+//g;
	$did2snippets{$did} = $snippet;
    }

    return \%did2snippets;
}

1;
