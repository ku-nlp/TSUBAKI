#!/usr/bin/env perl

# $Id$

# Extract pairs of a title and url from standard formatted data

use strict;
use utf8;
use Encode;
use Getopt::Long;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use PerlIO::gzip;
use File::stat;
use Error qw(:try);
use File::Path;

binmode(STDOUT, ':utf8');

my (%opt);
GetOptions(\%opt, 'files=s', 'url', 'title', 'verbose', 'zip=s', 'zip_tmp_dir=s');

if ($opt{zip}) {
    require Archive::Zip;
    require Archive::Zip::MemberRead;

    if ($opt{zip_tmp_dir} && ! -d $opt{zip_tmp_dir}) {
	mkpath $opt{zip_tmp_dir} or die "$! ($opt{zip_tmp_dir})";
    }
}

if (!defined $opt{url} && !defined $opt{title}) {
    $opt{url} = 1;
    $opt{title} = 1;
}


main();

sub main {
    if ($opt{zip}) {
	my $zip = Archive::Zip->new();
	die "$! ($opt{zip})" unless $zip->read($opt{zip}) == 'Archive::Zip::AZ_OK';

	foreach my $member ($zip->members()) {
	    my $file = $member->fileName();
	    $zip->extractMember($file, "$opt{zip_tmp_dir}/$file");
	    my ($name) = ($file =~ /([^\/]+)\.xml/);
	    open(READER, '<:gzip', "$opt{zip_tmp_dir}/$file") or die "$!";
	    binmode(READER, ':utf8');
	    &read_file("$opt{zip_tmp_dir}/$file", $name, *READER);
	    close READER;
	}
    }
    elsif ($opt{files}) {
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

	    &read_file($file, $name, *READER);
	    close READER;
	}
	close (FILES);
    }
}


sub read_file {
    my ($file, $name, $F) = @_;

    my $st = stat($file);
    my $size = 0;
    if ($st) {
	$size = $st->size;
    } else {
	print STDERR "$file cannot obtain file status.\n";
    }

    my $url = 'none';
    my $title = 'none';
    while (my $sf_tag = <$F>) {
	if ($opt{url}) {
	    if ($sf_tag =~ /Url=\"([^\"]*)\"/) {
		$url = $1;
		unless ($url) {
		    print STDERR "$file: URL is empty!\n" if $opt{verbose};
		    $url = 'none';
		}
	    }
	}

	if ($opt{title}) {
	    if ($sf_tag =~ /<RawString>([^<]+)<\/RawString>/) { # first RawString (maybe in Header)
		$title = $1;
		# スペースを_に置換 for English
		$title =~ s/ /_/g;
	    }
	}
	last if $title ne 'none';
    }
    if ($opt{url} && $opt{title}) {
	print "$name $url $title $size\n";
    }
    elsif ($opt{url}) {
	print "$name $url $size\n";
    }
    elsif ($opt{title}) {
	print "$name $title $size\n";
    }
}
