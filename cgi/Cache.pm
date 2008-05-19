package Cache;

# $Id$

# 検索キャッシュを管理するクラス

use strict;
use utf8;
use POSIX qw(strftime);
use Configure;
use Storable;

my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class) = @_;

    my %buf;
    my $cachelog = "$CONFIG->{CACHE_DIR}/log";
    open(READER, '<:utf8', $cachelog) or die;
    while (<READER>) {
	chop;
	my ($time, $key, $fp) = split("\t", $_);
	$buf{$key} = $fp;
    }
    close(READER);

    my $this = {cachedData => \%buf};

    bless $this;
}

sub save {
    my ($this, $query, $result) = @_;

    my $timestamp = strftime("%Y-%m-%d-%T", localtime(time));
    my $fname = $timestamp;
    my $filepath = sprintf("%s/%s", $CONFIG->{CACHE_DIR}, $fname);
    store($result, $filepath) or die;

    my $normalizedQuery = $query->normalize();
    my $cachelog = "$CONFIG->{CACHE_DIR}/log";
    open(WRITER, '>>:utf8', $cachelog) or die;
    print WRITER "$timestamp\t$normalizedQuery\t$filepath\n";
    close(WRITER);
}

sub load {
    my ($this, $query) = @_;

    my $normalizedQuery = $query->normalize();
    my $filepath = $this->{cachedData}{$normalizedQuery};

    my $result;
    if ($filepath) {
	$result = retrieve($filepath) or die;
    }

    return $result;
}

1;
