#!/usr/bin/env perl

# $Id$

# 拡張同位表現集合データベースを作成・テストするスクリプト

# Usage:
# For create:
# perl -I somewhere/Utils/perl make-ects-db.perl -coord_file coordinate_1028.txt -dfdb cns.10M.gen.df10.cdb -create
#
# For test:
# perl -I somewhere/Utils/perl make-ects-db.perl -query トランペット


use strict;
use utf8;
use Encode;
use Getopt::Long;
use ECTS;

binmode STDIN,  'encoding(euc-jp)';
binmode STDOUT, 'encoding(euc-jp)';

my %opt;
GetOptions(\%opt,
	   'create',
	   'coord_file=s',
	   'dfdb=s',
	   'bin_file=s',
	   'term2id=s',
	   'triedb=s',
	   'query=s',
	   'size_of_on_memory=i'
	   );

$opt{bin_file}           = 'ecs.db'    unless (defined $opt{bin_file});
$opt{triedb}             = 'offset.db' unless (defined $opt{triedb});
$opt{term2id}            = 'term2id'   unless (defined $opt{term2id});
$opt{size_of_on_memory}  = 1000000000  unless (defined $opt{size_of_on_memory});

if ($opt{create}) {
    &main4create();
} else {
    &main4retrieve();
}

sub main4retrieve {
    my $ecs = new ECTS(\%opt);
    my $set = $ecs->retrieve(Encode::decode('euc-jp', $opt{query}));
    my $cid = 1;
    foreach my $_set (@$set) {
	my $count = 1;
	foreach my $term (@$_set) {
	    printf ("class=%s num=%d term=%s\n", $cid, ,$count++, $term);
	}
	$cid++;
    }
}

sub main4create {
    my $ecs = new ECTS(\%opt);

    open (F, '<:encoding(euc-jp)', $opt{coord_file}) or die $!;
    while (<F>) {
	chop;

	my ($midasi, $coords) = split (/ /, $_);
	$ecs->add($midasi, $coords);
    }
    $ecs->close();
}
