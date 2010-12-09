#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use CDB_File;
use CDB_Writer;
use Getopt::Long;

our (%opt);
&GetOptions(\%opt, 'dir=s');
$opt{dir} = '.' unless $opt{dir};

my $word_cdb = new CDB_Writer("$opt{dir}/df.word.cdb", "df.word.cdb.keymap", 2.5 * 1024 * 1024 * 1024, 1000000);
my $dpnd_cdb = new CDB_Writer("$opt{dir}/df.dpnd.cdb", "df.dpnd.cdb.keymap", 2.5 * 1024 * 1024 * 1024, 1000000);

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
