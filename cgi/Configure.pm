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
# 環境によってパスを変える
my $CONFIG_FILE_PATH =  $DIRNAME . '/' . (($HOSTNAME =~ /iccc/) ? 'configure.nict' : 'configure');

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
	elsif ($_ =~ /STANDARD_FORMAT_LOCATION/) {
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
		$this->{DID2HOST}{$did} = $host;
	    }
	}
	elsif ($_ =~ /BLOCK_TYPE_DEFINITION/) {
	    my ($key, $file) = split (/\s+/, $_);
	    open (FILE, '<:utf8', $file) or die "$!";
	    while (<FILE>) {
		chop;
		my $line = $_;
		$line =~ s/#.*$//;
		next if ($line eq '');

		my ($attribute, $label, $tag, $chk_flag, $weight) = split (/\s/, $_);
		$this->{BLOCK_TYPE_DATA}{$tag}{attribute} = $attribute;
		$this->{BLOCK_TYPE_DATA}{$tag}{label} = $label;
		$this->{BLOCK_TYPE_DATA}{$tag}{tag} = $tag;
		$this->{BLOCK_TYPE_DATA}{$tag}{isChecked} = $chk_flag;
		$this->{BLOCK_TYPE_DATA}{$tag}{isDefaultChecked} = $chk_flag;
		$this->{BLOCK_TYPE_DATA}{$tag}{weight} = $weight;
		push (@{$this->{BLOCK_TYPE_KEYS}}, $tag);
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
	    my ($key, $value) = split(/\s+/, $_);

	    if ($value =~ /,/) {
		my @values = split(/,/, $value);
		$this->{$key} = \@values;
	    } else {
		$this->{$key} = $value;
	    }
	}
    }
    close(READER);


    if ($this->{IS_IPSJ_MODE} || $this->{IS_KUHP_MODE}) {
	foreach my $host (@{$this->{SNIPPET_SERVERS}}) {
	    push (@{$this->{IPSJ_SNIPPET_SERVERS}}, $host->{name});
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

sub getTsuruokaTaggerObj {
    my ($this) = @_;

    unless (defined $instance->{TSURUOKA_TAGGER}) {
	require TsuruokaTagger;
	$instance->{TSURUOKA_TAGGER} = new TsuruokaTagger(
	    {
		lemmatize  => 1,
		tagger_dir => $this->{TSURUOKA_TAGGER_DIR},
		format     => 'conll'
	    });
    }

    return $instance->{TSURUOKA_TAGGER}
}

sub getMaltParserObj {
    my ($this) = @_;

    unless (defined $instance->{MALT_PARSER}) {
	require MaltParser;
	$instance->{MALT_PARSER} = new MaltParser(
	    {
		lemmatize    => 1,
		parser_dir   => $this->{MALT_PARSER_DIR},
		java_command => $this->{JAVA_COMMAND}
	    });
    }

    return $instance->{MALT_PARSER};
}

sub getSynGraphObj {
    my ($this) = @_;

    unless (defined $instance->{SYNGRAPH}) {
	push (@INC, $instance->{SYNGRAPH_PM_PATH});
	require SynGraph;

	my $option = ();
	$option->{syndbcdb} = sprintf ("%s/../x86_64/syndb.cdb", $instance->{SYNDB_PATH});
	$instance->{SYNGRAPH} = new SynGraph(
	    $instance->{SYNDB_PATH},
	    undef, # KNPのオプション
	    $option
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
