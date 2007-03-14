#!/usr/bin/env perl

use strict;
use utf8;
use Encode;

my $outdir = shift(@ARGV);
my $N = 3;

foreach my $dir (@ARGV){
    opendir(DIR, $dir);
    my $fcnt = 0;
    foreach my $file (sort readdir(DIR)){
	next unless($file =~ /(\d+)\.xml\.gz/);
	print STDERR "\r$dir ($fcnt)" if($fcnt%13 == 0);
	$fcnt++;

	my $did = $1;
	my $fp = "$dir/$file";
	open(READER, "zcat $fp | ");
	$file =~ s/\.xml\.gz//;
#	open(WRITER2, ">  $outdir/$file.raw");
	my $rawstrings;
	my $ln = 1;
	my %indexes = ();
	while(<READER>){
	    if($_ =~ m!<RawString>([\s|\S]+?)</RawString>!){
#		printf WRITER2 ("%s %d %s\n", $file, $ln, $1);
		$ln++;

		my $rawstring = decode('utf8', $1);
		my $size = length($rawstring);
		for(my $i = 0; $i < $size; $i++){
		    for(my $j = 1; $j < $N + 1; $j++){
			next if($i + $j > $size);
			my $index = substr($rawstring, $i, $j);
			$indexes{$index} = 0 unless(exists($indexes{$index}));
			$indexes{$index} += 1;
#			push(@{$indexes[$j - 1]}, $index);
		    }
		}

#		foreach my $ngram_indexes (sort {length($indexes[$a]) <=> length($indexes[$b])} @indexes){
#		    foreach my $k (sort @{$ngram_indexes}){
#			print WRITER1 encode('euc-jp', $k) . "\n";
#		    }
#		}
	    }
	}
	close(READER);
	open(WRITER1, ">  $outdir/$file.idx3");
	foreach my $k (sort {$a cmp $b}keys %indexes){
	    my $v = $indexes{$k};
	    printf WRITER1 ("%s %d:%d\n", encode('utf8', $k), $file, $v);
	}
	close(WRITER1);
#	close(WRITER2);
    }
    print STDERR "\r$dir ($fcnt) done.\n";
    closedir(DIR);
}
