#!/usr/bin/env perl

# $Id$

# 通常検索用インデックスをひくプログラム

# Usage:
# perl seek_test.pl -idxdir /data/skeiji/idx_070828/dat1/anchor -type word -query '東京/とうきょう' -id 000

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Retrieve;
use Data::Dumper;
use QueryParser;

my (%opt);
GetOptions(\%opt, 'type=s', 'id=s', 'query=s', 'idxdir=s', 'dfdbdir=s', 'skippos', 'syngraph');

binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");

my $q_parser = new QueryParser({ DFDB_DIR => $opt{dfdbdir} });
my $query = $q_parser->parse(decode('euc-jp', $opt{query}),
			     { logical_cond_qk => 'AND',
			       syngraph => $opt{syngraph} });
my $ret = new Retrieve($opt{idxdir}, $opt{type}, $opt{skippos}, 1, 0, 0);

foreach my $group (@{$query->{keywords}[0]{"$opt{type}s"}}) {
    foreach my $e (@$group) {
	print STDERR "################\n";
	print STDERR $e->{string} . "\n";
	print STDERR "################\n";

	my $docs = $ret->search($e, {}, 1, 1, 1, $opt{syngraph});
	print STDERR Dumper($docs) . "\n";
    }
    print STDERR "======================\n";
}
