#!/usr/bin/env perl

# $Id$

# Usage: echo 動作確認 | perl -I $HOME/cvs/Utils/perl  -I../perl -I../cgi test-query-parser.perl

use strict;
use utf8;
use Unicode::Japanese;
use KNP::Result;
use Configure;
use Tsubaki::TermGroupCreater;

my $CONFIG = Configure::get_instance();

push (@INC, $CONFIG->{SYNGRAPH_PM_PATH});
push (@INC, $CONFIG->{UTILS_PATH});

require SynGraph;
my $SYNGRAPH = new SynGraph($CONFIG->{SYNDB_PATH});

my $opt;
$opt->{syngraph_option}{no_attach_synnode_in_wikipedia_entry} = 1;
$opt->{syngraph_option}{attach_wikipedia_info} = 1;
$opt->{syngraph_option}{wikipedia_entry_db} = $CONFIG->{WIKIPEDIA_ENTRY_DB};
$opt->{syngraph_option}{regist_exclude_semi_contentword} = 1;
$opt->{syngraph_option}{relation} = 1;
$opt->{syngraph_option}{antonym} = 1;
$opt->{syngraph_option}{hypocut_attachnode} = 9;

binmode (STDIN,  ':utf8');
binmode (STDOUT, ':utf8');

while (<STDIN>) {
    chop;

    my $knpresult = $CONFIG->{KNP}->parse(Unicode::Japanese->new($_)->h2z->getu);

    $knpresult->set_id(0);
    my $synresult = $SYNGRAPH->OutputSynFormat($knpresult, $opt->{syngraph_option}, $opt->{syngraph_option});

    my $root = &Tsubaki::TermGroupCreater::create(new KNP::Result($synresult));
    my $sexp = $root->to_S_exp();

    $sexp =~ s/\n/ /g;
    $sexp =~ s/\s+/ /g;

    print $sexp . "\n";
}
