#!/usr/bin/env perl

# $Id$

# Usage: echo 動作確認 | perl -I $HOME/cvs/Utils/perl  -I../perl -I../cgi test-query-parser.perl

use strict;
use utf8;
use Configure;
use QueryParser;
use Getopt::Long;

binmode (STDIN,  ':utf8');
binmode (STDOUT, ':utf8');

my $CONFIG = Configure::get_instance();
push (@INC, $CONFIG->{SYNGRAPH_PM_PATH});
push (@INC, $CONFIG->{UTILS_PATH});


my (%opt);
GetOptions(\%opt, 'syngraph', 'english');


my $queryParser = new QueryParser({IS_ENGLISH_VERSION => $opt{english}});
while (<STDIN>) {
    chop;

    my $queryObj = $queryParser->parse($_, \%opt);

    my $s_exp = $queryObj->{s_exp};
    $s_exp =~ s/\n/ /g;
    $s_exp =~ s/\s+/ /g;

    print $s_exp . "\n";
}
