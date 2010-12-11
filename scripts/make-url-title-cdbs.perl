#!/usr/bin/env perl

use strict;
use utf8;
use CDB_File;
use Getopt::Long;

our (%opt);
&GetOptions(\%opt, 'titledb=s', 'urldb=s');

&main();

sub main {
    my $fp = shift(@ARGV);

    my $titlecdb_name = $opt{titledb} ? $opt{titledb} : "$fp.title.cdb";
    my $urlcdb_name = $opt{urldb} ? $opt{urldb} : "$fp.url.cdb";

    my $titlecdb = new CDB_File ($titlecdb_name, "$titlecdb_name.$$") or die;
    my $urlcdb = new CDB_File ($urlcdb_name, "$urlcdb_name.$$") or die;

    open(READER, '<:utf8', $fp);
    while(<READER>){
	chop($_);
	my ($did, $url, $title) = split(' ', $_);

	$titlecdb->insert($did, $title);
	$urlcdb->insert($did, $url);
    }
    close(READER);

    $titlecdb->finish(); 
    $urlcdb->finish(); 
}
