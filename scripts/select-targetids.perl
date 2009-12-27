#!/usr/bin/env perl

use strict;
use utf8;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'ignore_version');

&main();

sub main {
    my %targetids = ();
    open (FILE, $ARGV[0]) or die "$!";
    while (<FILE>) {
	chop;
	my $fid = $_;

	$fid =~ s/\-\d+$// if ($opt{ignore_version});
	$targetids{$fid} = 1;
    }
    close (FILE);


    while (<STDIN>) {
	chop;
	my $file = $_;
	my $sid = &get_fid($file);

	print $file . "\n" if (exists $targetids{$sid});
    }
}

sub get_fid {
    my ($file) = @_;

    my ($fname) = ($file =~ /^.+\/([^\/]+)$/);
    my ($fid) = ($fname =~ /^((\d|\-)+)/);

    $fid =~ s/\-\d+$// if ($opt{ignore_version});

    return $fid;
}
