#!/usr/bin/perl -w

use strict;

my @lines = ();
my %head = ();

while (<STDIN>) {

	if (/^\s*$/) {
		# print $_;
		next;
	}

	my $line = $_;

	my @filed = split;

	my $name = $filed[2];

	if ($name eq "sentence" && @lines) {
		&printSentence();
		@lines = ();
		%head = ();
	}

	if ($name eq "cons") {

		my $headDtr;

		if ($line =~ m/^\d+\s+\d+\s+[^\s]+(\s.*)$/) {
			my $attrs = $1; ### with heading spaces

			my $self;

			if ($attrs =~ m/\sid="([^"]+)"/) {
				$self = $1;
			}
			else {
				die "cons without id attribute";
			}

			if ($attrs =~ m/\shead="([^"]+)"/) {
				$headDtr = $1;
			}
			else {
				die "cons without head attribute";
			}
	
			$head{$self} = $headDtr;
		}
		else {
			die "Annotation format error\n";
		}

		push(@lines, "$name:$headDtr:$line");
	}
	else {
		push(@lines, "$name:$line");
	}
}

if (@lines) {
	&printSentence();
}

exit 0;

sub printSentence {
	
	foreach my $line (@lines) {

		$line =~ s/^([^:]+)://;
		my $name = $1;

		if ($name eq "cons") {
			
			$line =~ s/^([^:]+)://;

			my $headDtr = $1;
			my $lexHead = &findLexHead($headDtr);

			chomp $line;
			print "$line lex_head=\"$lexHead\"\n";
		}
		else {
			print $line;
		}
	}

	return;
}

sub findLexHead {

	my $h = shift;

	if ($h =~ m/^t/) {
		return $h;
	}

	my $dtr = $head{$h};

	if (! $dtr) {
		die "Cannot follow parent-head relations to the leaf level for $h";
	}

	return &findLexHead($dtr);
}
