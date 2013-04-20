#!/usr/bin/env perl

# make a sid2origid DB

# Usage: make-sid2origid-db.perl sid2origid.cdb < filename2sid

# Input:
# FT922-6247.html 0000000000
# FT922-14247.html 0000000001
# ...

# $Id$

use CDB_File;
use strict;

$ARGV[0] or &usage;

sub usage {
    $0 =~ m|([^/]+)$|;
    print "Usage: $1 database\n";
    exit 1;
}

my $db = new CDB_File($ARGV[0], "$ARGV[0].$$") or die "new failed: $!\n";

while (<STDIN>) {
    chomp;
    my @temp = split(/\s/, $_, 2);
    $temp[0] =~ s/\.[^.]+$//; # delete an extension

    $db->insert($temp[1], $temp[0]);
}

$db->finish;
