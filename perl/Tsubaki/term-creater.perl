#!/usr/bin/env perl

# $Id$

# Usage:
# perl -I /somewhere/Utils/perl -I /somewhere/SearchEngine/scripts -I /somewhere/SearchEngine/cgi Tsubaki/term-creater.perl -query STRING

use strict;
use utf8;
use Encode;
use Data::Dumper;
use Getopt::Long;

use Configure;
use QueryParser;
use Tsubaki::TermGroup;
use Tsubaki::QueryAnalyzer;
use Tsubaki::TermGroupCreater;


my (%opt);
GetOptions(\%opt, 'query=s');

my $CONFIG = Configure::get_instance();
push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});

my $encoding;
if ($ENV{LANG} =~ /UTF8/) {
    $encoding = 'utf8';
}
elsif ($ENV{LANG} =~ /euc/) {
    $encoding = 'euc-jp';
} else {
    $encoding = 'shiftjis';
}


binmode (STDOUT, ":encoding($encoding)");
binmode (STDERR, ":encoding($encoding)");

&main();

sub main {

    # クエリの言語解析
    my $SYNGRAPH = $CONFIG->getSynGraphObj();
    my $knpresult = $CONFIG->{KNP}->parse(decode($encoding, $opt{query}));
    my $parser = new QueryParser();
    my $synresult = $parser->_runSynGraph($knpresult, ());


    # クエリ処理
    my $opt;
    $opt->{end_of_sentence_process} = 1;
    $opt->{telic_process} = 1;
    $opt->{CN_process} = 1;
    $opt->{NE_process} = 1;
    $opt->{modifier_of_NE_process} = 1;

    my $analyzer = new Tsubaki::QueryAnalyzer($opt);
    $analyzer->analyze($synresult,
		       {
			   end_of_sentence_process => $opt->{end_of_sentence_process},
			   telic_process => $opt->{telic_process},
			   CN_process => $opt->{CN_process},
			   NE_process => $opt->{NE_process},
			   modifier_of_NE_process => $opt->{modifier_of_NE_process}
		       });


    # S式の生成
    my $root = &Tsubaki::TermGroupCreater::create($synresult);
    print $root->to_S_exp() . "\n";
}
