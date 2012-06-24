#!/usr/bin/env perl

# $Id$

# Usage: echo 動作確認 | perl -I $HOME/cvs/Utils/perl  -I../perl -I../cgi test-query-parser.perl

use strict;
use utf8;
use Configure;
use QueryParser;
use Getopt::Long;
use Logger;

binmode (STDIN,  ':utf8');
binmode (STDOUT, ':utf8');

my $CONFIG = Configure::get_instance();
push (@INC, $CONFIG->{SYNGRAPH_PM_PATH});
push (@INC, $CONFIG->{UTILS_PATH});


my (%opt);
GetOptions(\%opt, 'syngraph', 'english', 'verbose', 'ignore_yomi', 'blocktype');
if ($opt{blocktype}) {
    $opt{blockTypes} = {'TT' => 1, 'MT' => 1, 'UB' => 1};
}

my $queryParser = new QueryParser({IS_ENGLISH_VERSION => $opt{english}});
while (<STDIN>) {
    chop;

    $opt{logger} = new Logger();
    my $queryObj = $queryParser->parse($_, \%opt);

    my $s_exp = $queryObj->{s_exp};
    $s_exp =~ s/\n/ /g;
    $s_exp =~ s/\s+/ /g;

    print $s_exp . "\n";

    if ($opt{verbose} && defined $opt{logger}->getParameter('ERROR_MSGS')) {
	# エラーを出力
	my $eid = 1;
	foreach my $errObj (@{$opt{logger}->getParameter('ERROR_MSGS')}) {
	    print "ERROR$eid: $errObj->{msg} @ $errObj->{owner}\n";
	    $eid++;
	}
    }
}
