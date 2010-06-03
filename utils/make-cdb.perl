#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use CDB_File;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'outf=s');

&main();

sub main {
    my $fp = shift(@ARGV);
    my $outf = ($opt{outf}) ? $opt{outf} : "$fp.cdb";
    my $tmpf = "$outf.$$";
    my $cdb = new CDB_File ($outf, $tmpf) or die $!;

    open(READER, $fp);
    while(<READER>){
	chop($_);
	my ($k, $v) = split(' ', $_);
	$cdb->insert($k, $v);
    }
    close(READER);
    $cdb->finish(); 
}
