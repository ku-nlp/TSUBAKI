#!/usr/bin/env/perl

use utf8;
use strict;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'rmfile=s', 'grmfile=s', 'sid2tid=s');

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

    if (-e $opt{sid2tid}) {
	open (FILE, $opt{sid2tid}) or die "$!\n";
	my @buf;
	while (<FILE>) {
	    chop;
	    my ($sid, $tid) = split (/ /, $_);
	    unless (exists $rmfiles{$sid}) {
		push (@buf, $sid);
	    }
	}
	close (FILE);

	foreach my $sid (sort @buf) {
	    print $sid . "\n";
	}
    }
    else {
	foreach my $dir (@ARGV) {
	    &retrieve($dir);
	}
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
