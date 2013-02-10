#!/usr/bin/env perl

# Update rmfiles

# Usage: $0 main_index_dir > new_rmfiles
#        main_index_dir contains url2sid and rmfiles
#        STDIN: new urls

use strict;

our $MAIN_DIR = $ARGV[0] ? $ARGV[0] : '.';

our %url2sid;
our %rmfiles;

open(URL2SID, "$MAIN_DIR/url2sid") or die;
while (<URL2SID>) {
    if (/^(\S+) (\S+)/) {
	$url2sid{$1} = $2;
    }
    else {
	warn("Invalid entry: $_");
    }
}
close(URL2SID);

if (open(RMFILES, "$MAIN_DIR/rmfiles")) {
    while (<RMFILES>) {
	chomp;
	$rmfiles{$_}++; # key is SID
    }
    close(RMFILES);
}

while (<STDIN>) {
    if (/^(\S+)/) {
	my $url = $1;
	if (exists($url2sid{$url})) { # this url exists in the main index
	    unless (exists($rmfiles{$url2sid{$url}})) { # this SID is not in the current rmfiles
		$rmfiles{$url2sid{$url}}++;
	    }
	}
    }
}

for my $sid (sort keys %rmfiles) {
    print $sid, "\n";
}
