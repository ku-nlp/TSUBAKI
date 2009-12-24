#!/usr/bin/env perl

use strict;
use utf8;
use File::Basename;
use Getopt::Long;

my %opt;
&GetOptions(\%opt,
	    "datadir=s",
	    "workspace=s",
	    "host=s",
	    "prefix=s",
	    "suffix=s",
	    "delfiles=s"
	    );

my $MAX_BYTE_OF_ARG_LENGTH = 10000;

&main();

sub main {
    my %buf;
    open (FILE, "> $opt{delfiles}") or die "$!";
    while (<STDIN>) {
	chop;
	if ($_ =~ /^delete (.*)$/) {
	    my ($host, $fpath) = split (":", $1);
	    next if ($host ne $opt{host});

	    print FILE $fpath . "\n";
	}
	elsif ($_ =~ /^move (.*)$/) {
	    my ($from, $to) = split (/ /, $1);
	    next if ($to ne $opt{host});

	    my ($host, $fpath) = split (":", $from);
	    push (@{$buf{$host}}, $fpath);
	}
    }
    close (FILE);

    foreach my $host (keys %buf) {
	my $count = 0;
	my @flist = ();
	my $sbuf = '';
	# コマンドの引数が長いとエラーが発生するので分割する
	foreach my $file (@{$buf{$host}}) {
#	    $file =~ s/$opt{datadir}\///g;
	    if (length($sbuf) > $MAX_BYTE_OF_ARG_LENGTH) {
		$count++;
		$sbuf = '';
	    }
	    my $sid = $file;
	    $sid =~ s/\-\d+$//;
	    push (@{$flist[$count]}, sprintf ("%s%04d/%s%07d/%s%s", $opt{prefix}, $sid / 1000000, $opt{prefix}, $sid / 1000, $sid, $opt{suffix}));
	    $sbuf .= ($file . " ");
	}

	my $count = 0;
	foreach my $files (@flist) {
	    my $files_str = join (" ", @$files);
	    my $tarf = sprintf ("%s2%s.%d.tar.gz", $host, $opt{host}, $count++);
	    printf "ssh %s 'cd %s ; tar czfk %s/%s %s 2> /dev/null' 2> /dev/null\n", $host, $opt{datadir}, $opt{workspace}, $tarf, $files_str;

	    printf "scp %s:%s/%s %s\n", $host, $opt{workspace}, $tarf, $opt{workspace};
	    printf "cd %s ; tar xzf %s/%s\n", $opt{workspace}, $opt{workspace}, $tarf;
	    printf "rm %s/%s\n", $opt{workspace}, $tarf;
	    printf "ssh %s 'rm %s/%s 2> /dev/null'\n", $host, $opt{workspace}, $tarf
	}
    }
}
