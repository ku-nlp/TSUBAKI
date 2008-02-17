#!/usr/bin/env perl

use strict;
use utf8;
use CDB_File;

&main();

sub main {
    my $fp = shift(@ARGV);

    my $titlecdb = new CDB_File ("$fp.title.cdb", "$fp.title.cdb.$$") or die;
    my $urlcdb = new CDB_File ("$fp.url.cdb", "$fp.url.cdb.$$") or die;

    open(READER, '<:utf8', $fp);
    while(<READER>){
	chop($_);
	my ($did, $url, $title) = split(' ', $_);

	# 文書IDを数値化
	$did += 0;

	$titlecdb->insert($did, $title);
	$urlcdb->insert($did, $url);
    }
    close(READER);

    $titlecdb->finish(); 
    $urlcdb->finish(); 
}
