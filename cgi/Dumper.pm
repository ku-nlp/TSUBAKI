package Dumper;

# $Id$

use strict;
use utf8;
use Data::Dumper;

sub dump_as_HTML {
    my ($obj) = @_;

    my $dumpstr = Dumper($obj);

    $dumpstr =~ s/</&lt;/g;
    $dumpstr =~ s/\n/<br>\n/g;
    $dumpstr =~ s/ /&nbsp;/g;

    return $dumpstr;
}

1;
