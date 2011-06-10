#!/usr/bin/env perl

# $Id$

# Extract pairs of a title and an url from standard formatted data

use strict;
use utf8;
use Getopt::Long;
use PerlIO::gzip;
use File::stat;
use Error qw(:try);

binmode(STDOUT, ':utf8');

my (%opt);
GetOptions(\%opt, 'files=s', 'url', 'title');

if (!defined $opt{url} && !defined $opt{title}) {
    $opt{url} = 1;
    $opt{title} = 1;
}


main();

sub main {
    open (FILES, $opt{files}) or die "$!";
    while (<FILES>) {
	chop;

	my $file = $_;
	my ($name) = ($file =~ /([^\/]+)\.xml/);
	try {
	    if ($file =~ /\.gz$/) {
		open(READER, '<:gzip', $file) or die "$!";
	    } else {
		open(READER, $file) or die "$!";
	    }
	    binmode(READER, ':utf8');
	} catch Error with {
	    my $err = shift;
	    print STDERR "Exception at line ", $err->{-line} ," in ", $err->{-file}, " (", $err->{-text}, " [$file])\n";
	};


	my $st = stat($file);
	my $size = 0;
	if ($st) {
	    $size = $st->size;
	} else {
	    print STDERR "$file cannot obtain file status.\n";
	}

	while (<READER>) {
	    my $sf_tag = <READER>;
	    my $url;
	    if ($opt{url}) {
		if ($sf_tag =~ /Url=\"([^\"]+)\"/) {
		    $url = $1;
		} else {
		    print STDERR "$file URL parse error.\n";
		}
	    }

	    my $title = 'none';
	    if ($opt{title}) {
		if ($sf_tag =~ /<RawString>([^<]+)<\/RawString>/) { # first RawString (in the line of sf_tag)
		    $title = $1;
		}
		else {
		    while (my $header_tag = <READER>) {
			if ($header_tag =~ /<RawString>([^<]+)<\/RawString>/) { # first RawString (maybe in Header)
			    $title = $1;
			    last;
			}
		    }
		}
		# スペースを_に置換 for English
		$title =~ s/ /_/g;
	    }

	    if ($opt{url} && $opt{title}) {
		print "$name $url $title $size\n";
	    } elsif ($opt{url}) {
		print "$name $url $size\n";
	    } elsif ($opt{title}) {
		print "$name $title $size\n";
	    }
	    last;
	}
	close(READER);
    }
    close (FILES);
}

