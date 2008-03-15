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

# 環境によってパスを変える
my $CONFIG_FILE_PATH = dirname($INC{'Configure.pm'}) . "/configure";

my %titledbs = ();
my %urldbs = ();

my $instance;

sub _new {
    my ($clazz) = @_;

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
	    my ($key, $host, $port, $dids) = split(/\t+/, $_);
	    $host =~ s/^\s*//;
	    $host =~ s/\s*$//;
	    $dids =~ s/^\s*//;
	    $dids =~ s/\s*$//;
	    push(@{$this->{SNIPPET_SERVERS}}, {name => $host, port => $port});
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
