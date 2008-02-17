#!/usr/bin/env perl

# $Id$

# Extract pairs of a title and an url from standard formatted data

use strict;
use utf8;
use Getopt::Long;

binmode(STDOUT, ':utf8');

my (%opt);
GetOptions(\%opt, 'dir=s', 'url', 'title', 'z');

main();

sub main {
    opendir(DIR, $opt{dir});
    foreach my $file (sort readdir(DIR)) {
	next if ($file eq '.' || $file eq '..');

	my ($name) = ($file =~ /(\d+)\.xml/);
	my $fp = "$opt{dir}/$file";
	if ($opt{z}) {
	    open(READER, "zcat $fp |");
	} else {
	    open(READER, $fp);
	}
	binmode(READER, ':utf8');

	while (<READER>) {
	    my $sf_tag = <READER>;
	    my $url;
	    if ($opt{url}) {
		if ($sf_tag =~ /Url="([^"]+)"/) {
		    $url = $1;
		} else {
		    open(ERR, ">> $opt{dir}.err");
		    print ERR "$file URL parse error.\n";
		    close(ERR);
		}
	    }

	    my $title;
	    if ($opt{title}) {
		my $header_tag = <READER>;
		unless ($header_tag =~ /Header/) {
		    print "$name $url null\n";
		} else {
		    my $title_tag = <READER>;
		    my $rawstring_tag = <READER>;
		    ($title) = ($rawstring_tag =~ /<RawString>([^<]+)<\/RawString>/);
		}
	    }

	    if ($opt{url} && $opt{title}) {
		print "$name $url $title\n";
	    } elsif ($opt{url}) {
		print "$name $url\n";
	    } elsif ($opt{title}) {
		print "$name $title\n";
	    }
	    last;
	}
	close(READER);
    }
    closedir(DIR);
}

