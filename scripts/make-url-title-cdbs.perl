#!/usr/bin/env perl

use strict;
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

    open(READER, $fp);
    while(<READER>){
	chop($_);
	my ($did, $url, @title_elements) = split(' ', $_);
	pop(@title_elements); # 最後のサイズを捨てる
	my $title = join(' ', @title_elements);

	$titlecdb->insert($did, $title);
	$urlcdb->insert($did, $url);
    }
    close(READER);

    $titlecdb->finish(); 
    $urlcdb->finish(); 
}
