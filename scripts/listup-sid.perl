#!/usr/bin/env/perl

use utf8;
use strict;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'rmfile=s', 'grmfile=s');

my %rmfiles = ();
if (-e $opt{rmfile}) {
    open (FILE, $opt{rmfile}) or die "$!\n";
    while (<FILE>) {
	chop;
	$rmfiles{$_} = 1;
    }
    close (FILE);
}

if (-e $opt{grmfile}) {
    open (FILE, $opt{grmfile}) or die "$!\n";
    while (<FILE>) {
	chop;
	$rmfiles{$_} = 1;
    }
    close (FILE);
}


&main();

sub main {
    foreach my $dir (@ARGV) {
	&retrieve($dir);
    }
}

sub retrieve {
    my ($dir) = @_;

    opendir (DIR, $dir) or die "$! ($dir)";

    my %buf = ();
    foreach my $sdir (readdir(DIR)) {
	next if ($sdir eq '.' || $sdir eq '..');
	next if ($sdir =~ /inlink/);

	my $fpath = "$dir/$sdir";
	if (-d $fpath) {
	    &retrieve($fpath);
	} else {
	    my $file = $sdir;
	    my ($sid) = ($file =~ /^((\d+)(?:-(\d+))?)/);

	    unless (exists $rmfiles{$sid}) {
		$buf{$sid} = 1;
	    }
	}
    }
    closedir (DIR);

    foreach my $sid (keys %buf) {
	print $sid . "\n";
    }
}
