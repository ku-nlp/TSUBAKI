package SnippetMakerAgent;

# $id: $

use strict;
use Encode;
use utf8;
use Storable;
use IO::Socket;
use IO::Select;
use MIME::Base64;
use QueryParser;

# 定数
my %DID2HOST = ();
$DID2HOST{'000'} = 'nlpc33';
$DID2HOST{'016'} = 'nlpc33';
$DID2HOST{'032'} = 'nlpc33';
$DID2HOST{'048'} = 'nlpc33';
$DID2HOST{'064'} = 'nlpc33';
$DID2HOST{'080'} = 'nlpc33';
$DID2HOST{'096'} = 'nlpc33';
$DID2HOST{'001'} = 'nlpc34';
$DID2HOST{'017'} = 'nlpc34';
$DID2HOST{'033'} = 'nlpc34';
$DID2HOST{'049'} = 'nlpc34';
$DID2HOST{'065'} = 'nlpc34';
$DID2HOST{'081'} = 'nlpc34';
$DID2HOST{'097'} = 'nlpc34';
$DID2HOST{'002'} = 'nlpc35';
$DID2HOST{'018'} = 'nlpc35';
$DID2HOST{'034'} = 'nlpc35';
$DID2HOST{'050'} = 'nlpc35';
$DID2HOST{'066'} = 'nlpc35';
$DID2HOST{'082'} = 'nlpc35';
$DID2HOST{'098'} = 'nlpc35';
$DID2HOST{'003'} = 'nlpc36';
$DID2HOST{'019'} = 'nlpc36';
$DID2HOST{'035'} = 'nlpc36';
$DID2HOST{'051'} = 'nlpc36';
$DID2HOST{'067'} = 'nlpc36';
$DID2HOST{'083'} = 'nlpc36';
$DID2HOST{'099'} = 'nlpc36';
$DID2HOST{'004'} = 'nlpc37';
$DID2HOST{'020'} = 'nlpc37';
$DID2HOST{'036'} = 'nlpc37';
$DID2HOST{'052'} = 'nlpc37';
$DID2HOST{'068'} = 'nlpc37';
$DID2HOST{'084'} = 'nlpc37';
$DID2HOST{'100'} = 'nlpc37';
$DID2HOST{'005'} = 'nlpc38';
$DID2HOST{'021'} = 'nlpc38';
$DID2HOST{'037'} = 'nlpc38';
$DID2HOST{'053'} = 'nlpc38';
$DID2HOST{'069'} = 'nlpc38';
$DID2HOST{'085'} = 'nlpc38';
$DID2HOST{'006'} = 'nlpc39';
$DID2HOST{'022'} = 'nlpc39';
$DID2HOST{'038'} = 'nlpc39';
$DID2HOST{'054'} = 'nlpc39';
$DID2HOST{'070'} = 'nlpc39';
$DID2HOST{'086'} = 'nlpc39';
$DID2HOST{'007'} = 'nlpc40';
$DID2HOST{'023'} = 'nlpc40';
$DID2HOST{'039'} = 'nlpc40';
$DID2HOST{'055'} = 'nlpc40';
$DID2HOST{'071'} = 'nlpc40';
$DID2HOST{'087'} = 'nlpc40';
$DID2HOST{'008'} = 'nlpc41';
$DID2HOST{'024'} = 'nlpc41';
$DID2HOST{'040'} = 'nlpc41';
$DID2HOST{'056'} = 'nlpc41';
$DID2HOST{'072'} = 'nlpc41';
$DID2HOST{'088'} = 'nlpc41';
$DID2HOST{'009'} = 'nlpc42';
$DID2HOST{'025'} = 'nlpc42';
$DID2HOST{'041'} = 'nlpc42';
$DID2HOST{'057'} = 'nlpc42';
$DID2HOST{'073'} = 'nlpc42';
$DID2HOST{'089'} = 'nlpc42';
$DID2HOST{'010'} = 'nlpc43';
$DID2HOST{'026'} = 'nlpc43';
$DID2HOST{'042'} = 'nlpc43';
$DID2HOST{'058'} = 'nlpc43';
$DID2HOST{'074'} = 'nlpc43';
$DID2HOST{'090'} = 'nlpc43';
$DID2HOST{'011'} = 'nlpc44';
$DID2HOST{'027'} = 'nlpc44';
$DID2HOST{'043'} = 'nlpc44';
$DID2HOST{'059'} = 'nlpc44';
$DID2HOST{'075'} = 'nlpc44';
$DID2HOST{'091'} = 'nlpc44';
$DID2HOST{'012'} = 'nlpc45';
$DID2HOST{'028'} = 'nlpc45';
$DID2HOST{'044'} = 'nlpc45';
$DID2HOST{'060'} = 'nlpc45';
$DID2HOST{'076'} = 'nlpc45';
$DID2HOST{'092'} = 'nlpc45';
$DID2HOST{'013'} = 'nlpc46';
$DID2HOST{'029'} = 'nlpc46';
$DID2HOST{'045'} = 'nlpc46';
$DID2HOST{'061'} = 'nlpc46';
$DID2HOST{'077'} = 'nlpc46';
$DID2HOST{'093'} = 'nlpc46';
$DID2HOST{'014'} = 'nlpc47';
$DID2HOST{'030'} = 'nlpc47';
$DID2HOST{'046'} = 'nlpc47';
$DID2HOST{'062'} = 'nlpc47';
$DID2HOST{'078'} = 'nlpc47';
$DID2HOST{'094'} = 'nlpc47';
$DID2HOST{'015'} = 'nlpc48';
$DID2HOST{'031'} = 'nlpc48';
$DID2HOST{'047'} = 'nlpc48';
$DID2HOST{'063'} = 'nlpc48';
$DID2HOST{'079'} = 'nlpc48';
$DID2HOST{'095'} = 'nlpc48';

my @HIGHLIGHT_COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", "880000", "00aa00", "886800", "004699", "990099");
my $TOOL_HOME = '/home/skeiji/local/bin';

my $KNP_PATH = $TOOL_HOME;
my $JUMAN_PATH = $TOOL_HOME;
my $SYNDB_PATH = '/home/skeiji/tmp/SynGraph/syndb/i686';

my $MAX_NUM_OF_WORDS_IN_SNIPPET = 100;

sub new {
    my ($class) = @_;

    my $this = {
	hosts => [],
	did2snippets => {},
	query_parser => undef
    };

    for (my $i = 33; $i < 49; $i++) {
	push(@{$this->{hosts}}, {name => sprintf("nlpc%02d", $i), port => 33335});
    }

    $this->{query_parser} = new QueryParser({
	KNP_PATH => $KNP_PATH,
	JUMAN_PATH => $JUMAN_PATH,
	SYNDB_PATH => $SYNDB_PATH,
	KNP_OPTIONS => ['-postprocess','-tab'] });
    
    bless $this;
}

sub create_snippets {
    my ($this, $query, $dids) = @_;

    # 文書IDを標準フォーマットを管理しているホストに割り振る
    my %host2dids = ();
    foreach my $did (@$dids) {
	push(@{$host2dids{$DID2HOST{sprintf("%03d", $did / 1000000)}}}, $did);
    }

    my $num_of_sockets = 0;
    my $selecter = IO::Select->new();
    for (my $i = 0; $i < scalar(@{$this->{hosts}}); $i++) {
	next unless (exists $host2dids{$this->{hosts}[$i]{name}});

	my $socket = IO::Socket::INET->new(
	    PeerAddr => $this->{hosts}[$i]{name},
	    PeerPort => $this->{hosts}[$i]{port},
	    Proto    => 'tcp' );
	
	$selecter->add($socket) or die;
	
 	# 検索クエリの送信
 	print $socket encode_base64(Storable::freeze($query), "") . "\n";
	print $socket "EOQ\n";

 	# 文書IDの送信
 	print $socket encode_base64(Storable::freeze($host2dids{$this->{hosts}[$i]{name}}), "") . "\n";
	print $socket "EOD\n";
	
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
	    }
	}
    }
}

sub get_snippets_for_each_did {
    my ($this) = @_;

    my %did2snippets = ();
    foreach my $did (keys %{$this->{did2snippets}}) {
	my $wordcnt = 0;
	my %snippets = ();
	my $sentences = $this->{did2snippets}{$did};

	# スコアの高い順に処理
	foreach my $sentence (sort {$b->{score_total} <=> $a->{score_total}} @{$sentences}) {
	    my $sid = $sentence->{sid};
	    for (my $i = 0; $i < scalar(@{$sentence->{reps}}); $i++) {
		$snippets{$sid} .= $sentence->{surfs}[$i];
		$wordcnt++;
		
		# スニペットが N 単語を超えた終了
		if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET) {
		    $snippets{$sid} .= " ...";
		    last;
		}
	    }
	    # ★ 多重 foreach の脱出に label をつかう
	    last if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET);
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
	$snippet = encode('utf8', $snippet) if (utf8::is_utf8($snippet));
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
	foreach my $sentence (sort {$b->{score} <=> $a->{score}} @{$sentences}) {
	    my $sid = $sentence->{sid};
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
		if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET) {
		    $snippets{$sid} .= " <b>...</b>";
		    last;
		}
	    }
	    # ★ 多重 foreach の脱出に label をつかう
	    last if ($wordcnt > $MAX_NUM_OF_WORDS_IN_SNIPPET);
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
	$snippet = encode('utf8', $snippet) if (utf8::is_utf8($snippet));
	$did2snippets{$did} = $snippet;
    }

    return \%did2snippets;
}

1;
