#!/usr/bin/env perl

# $Id$

# 通常検索用インデックスをひくプログラム

# Usage:
# perl seek_test.pl -dir /data/skeiji/idx_070828/dat1/anchor -type word -query '東京/とうきょう' -id 000

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Retrieve;
use Data::Dumper;

my (%opt);
GetOptions(\%opt, 'type=s', 'id=s', 'query=s', 'dir=s');

binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");

my $ret = new Retrieve($opt{dir}, $opt{type}, 1, 1, 0, 0);
my $docs = $ret->search({string => decode('euc-jp', $opt{query})}, {}, 1, 0, 0, 0);
print Dumper($docs) . "\n";
