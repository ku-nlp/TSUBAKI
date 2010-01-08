#!/usr/bin/env perl

use strict;
use utf8;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'remove', 'printid');

&main();

sub main {
    foreach my $dir (@ARGV) {
	&retrieve($dir);
    }
}

sub retrieve {
    my ($dir) = @_;

    opendir (DIR, $dir) or die "$!";

    my %bodybuf = ();
    my %inlnbuf = ();
    foreach my $sdir (readdir(DIR)) {
	next if ($sdir eq '.' || $sdir eq '..');

	my $fpath = "$dir/$sdir";
	if (-d $fpath) {
	    &retrieve($fpath);
	} else {
	    my $file = $sdir;
	    my ($sid, $version) = ($file =~ /^(\d+)(?:-(\d+))?/);
	    $version = 0 unless (defined $version);

	    my $buf = ($file =~ /inlink/) ? \%inlnbuf : \%bodybuf;

	    $buf->{$sid}{ver}{$version} = $file;
	    $buf->{$sid}{max} = $version if (!defined $buf->{$sid}{max} || $buf->{$sid}{max} < $version);
	}
    }

    foreach my $buf ((\%bodybuf, \%inlnbuf)) {
	foreach my $sid (keys %$buf) {
	    my $max = $buf->{$sid}{max};
	    if ($max < 1) {
		# Nothing to do.
	    } else {
		foreach my $version (keys %{$buf->{$sid}{ver}}) {
		    if ($version != $max) {
			my $file = $dir . "/" . $buf->{$sid}{ver}{$version};
			if ($opt{remove}) {
			    unlink $file;
			    print $file . " is removed.\n";
			} else {
			    if ($opt{printid}) {
				my $basename = $buf->{$sid}{ver}{$version};
				$basename =~ s/\.xml.gz$//;
				print $basename . "\n";
			    } else {
				print $file . " is a candidate.\n";
			    }
			}
		    }
		}
	    }
	}
    }
    closedir (DIR);
}
