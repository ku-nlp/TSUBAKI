#!/usr/bin/env perl

# $Id$

# 標準フォーマットを管理しているホストを調べる

use strict;
use utf8;
use SidRange;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'flist=s', 'stdin', 'save', 'suffix=s', 'sid_range=s', 'sids_on_update_node=s');

&main();

sub main {
    my $range = new SidRange(\%opt);

    if ($opt{flist}) {
	open (READER, $opt{flist}) or die "$!";
	while (<READER>) {
	    chop;
	    my $file = $_;

	    my ($dir, $name) = ($file =~ /(.+?)\/([^\/]+)$/);
	    my ($did) = ($name =~ /^(\d+)/);

	    my $host = $range->lookup($did);
	    print $file . " " . $host . "\n";
	}
	close (READER);
    }
    elsif ($opt{stdin}) {
	my %buf = ();
	while (<STDIN>) {
	    chop;
	    my $did = $_;
	    my $host = $range->lookup($did);
	    if ($opt{save}) {
		push(@{$buf{$host}}, $did);
	    } else {
		print $did . " " . $host . "\n";
	    }
	}

	if ($opt{save}) {
	    while (my ($host, $dids) = each %buf) {
		if ($opt{suffix}) {
		    open (WRITER, sprintf ("> %s.remove-sid.%s", $host, $opt{suffix}));
		} else {
		    open (WRITER, sprintf ("> %s.remove-sid", $host));
		}

		foreach my $did (@{$buf{$host}}) {
		    print WRITER $did . "\n";
		}
		close (WRITER);
	    }
	}
    }
    else {
	foreach my $did (@ARGV) {
	    my $host = $range->lookup($did);
	    print $did . " " . $host . "\n";
	}
    }
}
