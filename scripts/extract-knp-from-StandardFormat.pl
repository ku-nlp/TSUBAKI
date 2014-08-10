#!/usr/bin/env perl

# usage: gzip -dc /somewhere/XXX.xml.gz | perl extract-knp-from-StandardFormat.pl

use strict;
use utf8;
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
use StandardFormat;
use KNP::Result;
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'fid=s');

my $standard_format = new StandardFormat;
my $buf;
while (<>) {
    $buf .= $_;
}

my $knp_objects = $standard_format->get_knp_objects($buf, defined $opt{fid} ? $opt{fid} : undef);
for my $knp_result (@$knp_objects) {
    print $knp_result->all;
}

