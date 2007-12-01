#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use CDB_File;
use Encode;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'type=s', 'id=s', 'query=s', 'dir=s');

my @offsets;
opendir(DIR, $opt{dir});
foreach my $file (readdir(DIR)) {
    next unless ($file =~ /offset$opt{id}\.$opt{type}\.cdb/);

    my $fp = "$opt{dir}/$file";
    tie my %offset, 'CDB_File', $fp or die;
    push(@offsets, \%offset);
}
closedir(DIR);

my $offset = undef;
foreach my $offsetdb (@offsets) {
    $offset = $offsetdb->{decode('euc-jp', $opt{query})};
    last if (defined $offset);
}

my $idxfile = sprintf("%s/idx%s.%s.dat", $opt{dir}, $opt{id}, $opt{type});
print $idxfile . "\n";
open(DAT, $idxfile) or die;
my $char;
my $buf;
my @str;
my @docs;
my $position = 1;
seek(DAT, $offset, 0) or die $!;
while (read(DAT, $char, 1)) {
    if (unpack('c', $char) != 0) {
	push(@str, $char);
    }
    else {
	# 最初はキーワード（情報としては冗長）
	$buf = join('', @str);
	@str = ();

	# 次にキーワードの文書頻度
	read(DAT, $buf, 4);
	my $ldf = unpack('L', $buf);

	for (my $j = 0; $j < $ldf; $j++) {
	    read(DAT, $buf, 4);
	    my $did = unpack('L', $buf);
	    $docs[$j]->{did} = $did;
	}

# 	for (my $j = 0; $j < $ldf; $j++) {
# 	    read(DAT, $buf, 2);
# 	    my $freq = unpack('S', $buf);
# 	    $docs[$j]->{freq} = $freq / 1000;
# 	    print $freq . "\n";
# 	}

	read(DAT, $buf, 4);
	my $poss_size = unpack('L', $buf);
	read(DAT, $buf, 4);
	my $frqs_size = unpack('L', $buf);

	my $total_bytes = 0;
	$total_bytes = 0;
	for(my $i = 0; $total_bytes < $poss_size; $i++) {
	    read(DAT, $buf, 4);
	    my $size = unpack('L', $buf);
	    for (my $j = 0; $j < $size; $j++) {
		read(DAT, $buf, 4);
		my $pos = unpack('L', $buf);
		push(@{$docs[$i]->{poss}}, $pos);
	    }
	    $total_bytes += (($size + 1) * 4);
	}

	$total_bytes = 0;
	for(my $i = 0; $total_bytes < $frqs_size; $i++) {
	    read(DAT, $buf, 4);
	    my $size = unpack('L', $buf);
	    for (my $j = 0; $j < $size; $j++) {
		read(DAT, $buf, 2);
		my $freq = unpack('S', $buf);
		push(@{$docs[$i]->{freqs}}, $freq / 1000);
	    }
	    $total_bytes += (($size * 2) + 4);
	}
	last;
    }
}
close(DAT);

foreach my $d (@docs) {
    print "$d->{did}=did\n";
#   print "$d->{freq}=freq\n";

    if ($position > 0) {
	foreach my $pos (@{$d->{poss}}) {
	    print "$pos,";
	}
	print "=poss\n";

	foreach my $freq (@{$d->{freqs}}) {
	    print "$freq,";
	}
	print "=freqs\n";
    }
}
