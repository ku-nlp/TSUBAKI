#!/usr/bin/env perl

use strict;
use utf8;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'outdir=s', 'suffix=s', 'split=s', 'xmlfiles=s', 'termfiles=s', 'rmfiles=s', 'verbose');

$opt{split} = 1 unless (defined $opt{split});
$opt{outdir} = "." unless (defined $opt{outdir});

&main();

sub main {
    my $xmlfiles = &load($opt{xmlfiles});
    my $tmfiles  = &load($opt{termfiles});
    my $rmfiles  = &load($opt{rmfiles});


    my @buf;
    my $count = 0;
    while (my ($fid, $file) = each %$xmlfiles) {
	# rmfiles に登録されているのでインデキシングの対象外
	if (exists $rmfiles->{$fid}) {
	    print STDERR "[SKIP] " . $file . " is a rmfile.\n" if ($opt{verbose});
	    next;
	}

	# 既に term ファイルがあるので対象外
	if (exists $tmfiles->{$fid}) {
	    print STDERR "[SKIP] " . $file . " is already constracted its termfile.\n" if ($opt{verbose});
	    next;
	}

	push (@{$buf[$count++/$opt{split}]}, $file);
    }

    my $num = 1;
    foreach my $files (@buf) {
	if ($opt{suffix}) {
	    open (WRITER, sprintf ("> %s/flist.%05d.%s", $opt{outdir}, $num, $opt{suffix}));
	} else {
	    open (WRITER, sprintf ("> %s/flist.%05d", $opt{outdir}, $num));
	}

	foreach my $file (@$files) {
	    print WRITER $file . "\n";
	}
	close (WRITER);
	$num++;
    }
}

sub load {
    my ($file) = @_;

    my %buf;
    if (-e $file) {
	open (FILE, $file) or die "$!";
	while (<FILE>) {
	    chop;
	    $buf{&get_fid($_)} = $_;
	}
	close (FILE);
    }

    return \%buf;
}

sub get_fid {
    my ($file) = @_;

    my ($fname) = ($file =~ /^.+\/([^\/]+)$/);
    my ($fid) = ($fname =~ /^((\d|\-)+)/);

    return $fid;
}
