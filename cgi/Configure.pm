package Configure;

# 検索エンジンの設定ファイルと各モジュールのブリッジ
# Singleton実装

use strict;
use utf8;
use File::Basename;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $HOSTNAME = `hostname`;
my $DIRNAME = dirname($INC{'Configure.pm'});
# 環境によってパスを変える
my $CONFIG_FILE_PATH =  $DIRNAME . '/' . (($HOSTNAME =~ /nlpc/) ? 'configure' : 'configure.nict');

my %titledbs = ();
my %urldbs = ();

my $instance;

sub _new {
    my ($clazz, $opts) = @_;
    my $this;
    open(READER, '<:utf8', $CONFIG_FILE_PATH) or die "$! ($CONFIG_FILE_PATH\)n";
    while (<READER>) {
	next if ($_ =~ /^\#/);
	next if ($_ =~ /^\s*$/);

	chop;
	if ($_ =~ /SEARCH_SERVERS/) {
	    my ($key, $host, $ports) = split(/\t+/, $_);
	    $host =~ s/^\s*//;
	    $host =~ s/\s*$//;
	    $ports =~ s/^\s*//;
	    $ports =~ s/\s*$//;
	    foreach my $p (split(/,/, $ports)) {
		push(@{$this->{$key}}, {name => $host, port => $p});
	    }
	}
	elsif ($_ =~ /STANDARD_FORMAT_LOCATION/) {
	    my ($key, $host, $ports, $dids) = split(/\t+/, $_);
	    $host =~ s/^\s*//;
	    $host =~ s/\s*$//;
	    $dids =~ s/^\s*//;
	    $dids =~ s/\s*$//;
	    push(@{$this->{SNIPPET_SERVERS}}, {name => $host, ports => []});
	    foreach my $port (split(/,/, $ports)) {
		push(@{$this->{SNIPPET_SERVERS}[-1]{ports}}, $port);
	    }

	    foreach my $did (split(/,/, $dids)) {
		$this->{DID2HOST}{$did} = $host;
	    }
	}
	else {
	    my ($key, $value) = split(/\t+/, $_);

	    if ($value =~ /,/) {
		my @values = split(/,/, $value);
		$this->{$key} = \@values;
	    } else {
		$this->{$key} = $value;
	    }
	}
    }
    close(READER);

    if ($opts->{debug}) {
	print "* jmn -> $this->{JUMAN_COMMAND}\n";
	print "* knp -> $this->{KNP_COMMAND}\n";
	print "* knprcflie -> $this->{KNP_RCFILE}\n";
	print "* knpoption -> ", join(",", @{$this->{KNP_OPTIONS}}) . "\n\n";

	print "* create knp object...";
    }

    $this->{KNP} = new KNP(
	-Command => $this->{KNP_COMMAND},
	-Option => join(' ', @{$this->{KNP_OPTIONS}}),
	-Rcfile => $this->{KNP_RCFILE},
	-JumanRcfile => $this->{JUMAN_RCFILE},
	-JumanCommand => $this->{JUMAN_COMMAND});

    print " done.\n" if ($opts->{debug});

    bless $this, $clazz;
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
