package Tsubaki::CacheManager;

# $Id$

# 検索キャッシュを管理するクラス

use strict;
use utf8;
use POSIX qw(strftime);
use Configure;
use Storable qw(nstore retrieve);

my $CONFIG = Configure::get_instance();

# コンストラクタ
sub new {
    my ($class) = @_;

    my %data;
    my %mode;
    unless ($CONFIG->{DISABLE_CACHE}) {
	my $cachelog = "$CONFIG->{CACHE_DIR}/log";
	# log ファイルがなければ作成する
	unless (-f $cachelog) {
	    open (W, "> $cachelog") or die $!; close (W) or die $!;
	    chmod(0777, $cachelog) or die $!;
	}

	open(READER, '<:utf8', $cachelog) or die;
	while (<READER>) {
	    chop;
	    my ($time, $mode, $key, $file) = split("\t", $_);
	    $data{$key} = $file;
	    $mode{$key} = $mode;

	}
	close(READER);
    }

    my $this;
    $this->{data} = \%data;
    $this->{mode} = \%mode;

    bless $this;
}

sub save {
    my ($this, $key, $result, $mode) = @_;

    my $timestamp = strftime("%Y-%m-%d-%T", localtime(time));
    my $fname = $timestamp;
    my $filepath = sprintf("%s/%s", $CONFIG->{CACHE_DIR}, $fname);

    if ($mode eq 'OBJ') {
	nstore ($result, $filepath) or die $!;
    }
    elsif ($mode eq 'TXT') {
	open (F, "> $filepath") or die $!;
	print F $result;
	close (F);
    }
    else {
	nstore ($result, $filepath) or die $!;
	$mode = 'OBJ';
    }


    my $cachelog = "$CONFIG->{CACHE_DIR}/log";
    open(WRITER, '>>:utf8', $cachelog) or die;
    print WRITER "$timestamp\t$mode\t$key\t$filepath\n";
    close(WRITER);
}

sub exists {
    my ($this, $key) = @_;

    # 英語のときはキャッシュを使わない
    return 0 if $CONFIG->{IS_ENGLISH_VERSION};

    return exists $this->{cachedData}{$key};
}

sub load {
    my ($this, $key) = @_;

    # 英語のときはキャッシュを使わない
    return undef if $CONFIG->{IS_ENGLISH_VERSION};

    my $filepath = $this->{data}{$key};

    my $result;
    if ($filepath) {
	if ($this->{mode}{$key} eq 'OBJ') {
	    $result = retrieve($filepath) or die $!;
	}
	elsif ($this->{mode}{$key} eq 'TXT') {
	    open (F, $filepath) or die $!;
	    while (<F>) {
		$result .= $_;
	    }		
	    close (F);
	}
	else {
	    $result = retrieve($filepath) or die $!;
	}
    }

    return $result;
}

1;
