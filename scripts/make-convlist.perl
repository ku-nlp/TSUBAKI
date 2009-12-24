#!/usr/bin/env perl

use strict;
use utf8;
use File::Basename;
use Getopt::Long;
use CDB_Reader;

my %opt;
&GetOptions(\%opt,
	    "oldfiles=s",
	    "newfiles=s",
	    "rmfiles=s",
	    "hosts=s",
	    "num_of_files_per_host=s",
	    "sid_range=s",
	    "suffix=s"
	    );

$opt{num_of_files_per_host} = 1000000 unless (defined $opt{num_of_files_per_host});

&main();

sub main {
    my $map = new CDB_Reader($opt{oldfiles});

    my @hosts;
    open (FILE, $opt{hosts}) or die "$!";
    while (<FILE>) {
	chop;
	my ($host, @etc) = split (/ /, $_);
	if ($opt{suffix}) {
	    push (@hosts, sprintf ("%s.%s", $host, $opt{suffix}));
	} else {
	    push (@hosts, sprintf ("%s", $host));
	}
    }
    close (FILE);

    my %rmfiles;
    if ($opt{rmfiles}) {
	open (FILE, $opt{rmfiles}) or die "$!";
	while (<FILE>) {
	    chop;
	    $rmfiles{$_} = 1;
	}
	close (FILE);
    }

    my $i = 0;
    my $cnt = 0;
    my @newfiles;
    open (FILE, $opt{newfiles}) or die "$!";
    open (SID_RANGE, "> $opt{sid_range}") or die "$!";
    while (<FILE>) {
	chop;
	my $line = $_;
	if ($cnt >= $opt{num_of_files_per_host}) {
	    my $host = $hosts[$i++];
	    foreach my $file (@newfiles) {
		next if (exists $rmfiles{$file});

		if ($i % 1000 == 0) {
 		    $map->close();
 		    $map = new CDB_Reader($opt{oldfiles});
		}

		my $value = $map->get($file, {exhaustive => 1});
		if (!defined $value) {
		    printf "copy %s\n", $file;
		} else {
		    my ($_host, $fpath) = split (":", $value);
		    if ($host ne $_host) {
			printf "move %s:%s %s\n", $_host, $fpath, $host;
			printf "delete %s:%s\n", $_host, $fpath;
		    }
		}
	    }
	    print STDERR scalar (@newfiles) . " " . $newfiles[0] . "\n";
	    print SID_RANGE $host . " " . $newfiles[-1] . "\n";

	    $cnt = 0;
	    @newfiles = ();
	}
	$cnt++;
	push (@newfiles, $line);
    }
    close (FILE);

    if (scalar (@newfiles) > 0) {
	my $host = $hosts[$i++];
	foreach my $file (@newfiles) {
	    next if (exists $rmfiles{$file});
	    
	    my $value = $map->get($file, {exhaustive => 1});
	    if (!defined $value) {
		printf "copy %s\n", $file;
	    } else {
		my ($_host, $fpath) = split (":", $value);
		if ($host ne $_host) {
		    printf "move %s:%s %s\n", $_host, $fpath, $host;
		    printf "delete %s:%s\n", $_host, $fpath;
		}
	    }
	}
	print STDERR scalar (@newfiles) . " " . $newfiles[0] . "\n";
	print SID_RANGE $host . " " . $newfiles[-1] . "\n";
    }
    close (SID_RANGE);


    foreach my $file (keys %rmfiles) {
	my $value = $map->get($file, {exhaustive => 1});
	my ($host, $fpath) = split (":", $value);
	printf "delete %s:%s\n", $host, $fpath;
    }
}
