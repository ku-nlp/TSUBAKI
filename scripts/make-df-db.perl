#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use CDB_File;
use CDB_Writer;

my $word_cdb = new CDB_Writer("df.word.cdb", "df.word.cdb.keymap", 2.5 * 1024 * 1024 * 1024, 1000000);
my $dpnd_cdb = new CDB_Writer("df.dpnd.cdb", "df.dpnd.cdb.keymap", 2.5 * 1024 * 1024 * 1024, 1000000);

while (<STDIN>) {
    chop($_);
    my($k, $v) = split(' ', $_);
    if ($k =~ /\-\>/) {
	$dpnd_cdb->add($k, $v);
    } else {
	$word_cdb->add($k, $v);
    }
}

$word_cdb->close();
$dpnd_cdb->close();
