package Configure;

# 検索エンジンの設定ファイルと各モジュールのブリッジ
# Singleton実装

use strict;
use utf8;
use File::Basename;
use KNP;
use Error qw(:try);
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $HOSTNAME = `hostname`;
my $DIRNAME = dirname($INC{'Configure.pm'});
my $CONFDIRNAME = $DIRNAME . '/../conf';

# 設定ファイル名(default: configure)をtsubaki-cgi.confから読み込む
our $CONFIG_FILE_NAME;
require "$DIRNAME/tsubaki-cgi.conf";
my $CONFIG_FILE_PATH =  $CONFDIRNAME . '/' . $CONFIG_FILE_NAME;

my %titledbs = ();
my %urldbs = ();

my $instance;

sub _new {
    my ($clazz, $opts) = @_;
    my $this;
    my %downservers;
    open(READER, '<:utf8', $CONFIG_FILE_PATH) or die "$! ($CONFIG_FILE_PATH\)n";
    while (<READER>) {
	next if ($_ =~ /^\#/);
	next if ($_ =~ /^\s*$/);

	chop;

	# ダウンしているサーバーを検出し利用しないようにする
	if ($_ =~ /SERVER_STATUS_LOG/) {
	    my ($key, $logfile) = split(/\s+/, $_);

	    if (open (F, $logfile)) {
		while (<F>) {
		    next if ($_ =~ /alive!$/);

		    my ($host, $is, $down) = split (/ /, $_);
		    $downservers{$host} = 1;
		}
		close (F);
	    } else {
		if ($opts->{debug}) {
		    print STDERR "[WARNING] $logfile is * NOT * found!\n";
		}
	    }
	}

	if ($_ =~ /SEARCH_SERVERS/) {
	    my ($key, $host, $ports) = split(/\s+/, $_);
	    $host =~ s/^\s*//;
	    $host =~ s/\s*$//;
	    $ports =~ s/^\s*//;
	    $ports =~ s/\s*$//;

	    next if (exists $downservers{$host});

	    foreach my $p (split(/,/, $ports)) {
		push(@{$this->{$key}}, {name => $host, port => $p});
	    }
	}
	elsif ($_ =~ /SNIPPET_SERVERS/) {
	    my ($key, $host, $ports, $dids) = split(/\s+/, $_);
	    $host =~ s/^\s*//;
	    $host =~ s/\s*$//;
	    $dids =~ s/^\s*//;
	    $dids =~ s/\s*$//;

	    next if (exists $downservers{$host});

	    push(@{$this->{SNIPPET_SERVERS}}, {name => $host, ports => []});
	    foreach my $port (split(/,/, $ports)) {
		push(@{$this->{SNIPPET_SERVERS}[-1]{ports}}, $port);
	    }

	    foreach my $did (split(/,/, $dids)) {
		if (length($did) < 4) { # SnippetMakerAgent.pmで4桁でチェックするため、短い場合は0で埋めておく
		    $did = '0' x (4 - length($did)) . $did;
		}
		$this->{DID2HOST}{$did} = $host;
	    }
	}
	elsif ($_ =~ /BLOCK_TYPE_DEFINITION/) {
	    my ($key, $file) = split (/\s+/, $_);
	    open (FILE, '<:utf8', $file) or die "$!";
	    while (<FILE>) {
		chomp;
		my $line = $_;
		$line =~ s/#.*$//;
		next if ($line eq '');

		my ($attribute, $label, $tag, $chk_flag, $weight, $mask) = split (/\s/, $_);
		$this->{BLOCK_TYPE_DATA}{$tag}{attribute} = $attribute;
		$this->{BLOCK_TYPE_DATA}{$tag}{label} = $label;
		$this->{BLOCK_TYPE_DATA}{$tag}{tag} = $tag;
		$this->{BLOCK_TYPE_DATA}{$tag}{isChecked} = $chk_flag;
		$this->{BLOCK_TYPE_DATA}{$tag}{isDefaultChecked} = $chk_flag;
		$this->{BLOCK_TYPE_DATA}{$tag}{weight} = $weight;
		$this->{BLOCK_TYPE_DATA}{$tag}{mask} = $mask;
	    }
	    close (FILE);
	}
	elsif ($_ =~ /STOP_TERMS/) {
	    my ($key, $terms) = split (/\s+/, $_);
	    foreach my $term (split(/,/, $terms)) {
		$this->{STOP_TERMS}{$term} = 1;
	    }
	}
	else {
	    my ($key, $value) = split(/\s+/, $_, 2);

	    if ($value =~ /,/) {
		my @values = split(/,/, $value);
		$this->{$key} = \@values;
	    } else {
		$this->{$key} = $value;
	    }
	}
    }
    close(READER);


    if ($this->{IS_KUHP_MODE}) {
	foreach my $host (@{$this->{SNIPPET_SERVERS}}) {
	    push (@{$this->{KUHP_SNIPPET_SERVERS}}, $host->{name});
	}
    }



    if ($opts->{debug}) {
	print "* jmn -> $this->{JUMAN_COMMAND}\n";
	print "* knp -> $this->{KNP_COMMAND}\n";
	print "* knprcflie -> $this->{KNP_RCFILE}\n";
	print "* knpoption -> ", join(",", @{$this->{KNP_OPTIONS}}) . "\n\n";

	print "* create knp object...";
    }

    try {
	# 英語モード以外ではKNPオブジェクトを作る
	unless ($this->{IS_ENGLISH_VERSION}) {
	    $this->{KNP} = new KNP(
		-Command      => $this->{KNP_COMMAND},
		-Option       => join(' ', @{$this->{KNP_OPTIONS}}),
		-Rcfile       => $this->{KNP_RCFILE},
		-JumanRcfile  => $this->{JUMAN_RCFILE},
		-JumanCommand => $this->{JUMAN_COMMAND});
	}
    } catch Error with {
	printf STDERR (qq([ERROR] Can\'t create a parser object!\n));
	exit;
    };

    print " done.\n" if ($opts->{debug});

    bless $this;
}

sub getEnglishParserObj {
    my ($this) = @_;

    unless (defined $instance->{ENGLISH_PARSER}) {
	if ($this->{ENGLISH_PARSER_DIR} =~ /malt/) {
	    require MaltParser;
	    $instance->{ENGLISH_PARSER} = new MaltParser({lemmatize    => 1,
							  output_sf    => 1,
							  parser_options => $this->{ENGLISH_PARSER_OPTIONS},
							  tagger_dir   => $this->{ENGLISH_TAGGER_DIR},
							  java_command => $this->{JAVA_COMMAND}
							 });
	}
	elsif ($this->{ENGLISH_PARSER_DIR} =~ /stanford-parser/) {
	    require StanfordParser;
	    $instance->{ENGLISH_PARSER} = new StanfordParser({lemmatize    => 1,
							      output_sf    => 1,
							      parser_dir    => $this->{ENGLISH_PARSER_DIR},
							      java_command => $this->{JAVA_COMMAND}
							     });
	}
	else {
	    require EnjuWrapper;
	    $instance->{ENGLISH_PARSER} = new EnjuWrapper({parser_dir  => $this->{ENGLISH_PARSER_DIR},
							  });
	}
    }

    return $instance->{ENGLISH_PARSER};
}

sub getSynGraphObj {
    my ($this, $opt) = @_;

    unless (defined $instance->{SYNGRAPH}) {
	push (@INC, $instance->{SYNGRAPH_PM_PATH});
	require SynGraph;

	my $regnode_option = ();

	# Wikipediaの見出し語に対する設定
	$regnode_option->{no_attach_synnode_in_wikipedia_entry} = 1;
	$regnode_option->{attach_wikipedia_info} = 1;
	$regnode_option->{wikipedia_entry_db} = $opt->{wikipedia_entry_db} if ($opt->{wikipedia_entry_db});

	# 上位語付与の設定
	$regnode_option->{relation} = ($opt->{hyponymy}) ? 1 : 0;
	$regnode_option->{relation_recursive} = ($opt->{hyponymy}) ? 1 : 0;
	$regnode_option->{hypocut_attachnode} = $opt->{hypocut} if $opt->{hypocut};

	# 反義語付与の設定
	$regnode_option->{antonym} = ($opt->{antonymy}) ? 1 : 0;

	# 準内容語を除いたものもノードに登録するオプション(ネットワーク化 -> ネットワーク, 深み -> 深い)
	my $syngraph_option = {
	    regist_exclude_semi_contentword => 1,
	    no_regist_adjective_stem => $opt->{no_regist_adjective_stem},
	    db_on_memory => $opt->{syndb_on_memory}
	};
	$syngraph_option->{no_attach_synnode_in_wikipedia_entry} = 1;
	$syngraph_option->{attach_wikipedia_info} = 1;
	$syngraph_option->{wikipedia_entry_db} = $opt->{wikipedia_entry_db} if ($opt->{wikipedia_entry_db});



	$regnode_option->{syndbcdb} = sprintf ("%s/syndb.cdb", $instance->{SYNDB_PATH});
	$instance->{SYNGRAPH} = new SynGraph(
	    $instance->{SYNDB_PATH},
	    undef,
	    $regnode_option
	    );
    }

    return $instance->{SYNGRAPH};
}

sub get_instance {
    if ($instance) {
	return $instance;
    } else {
	$instance = _new(@_);
	return $instance;
    }
}

1;
