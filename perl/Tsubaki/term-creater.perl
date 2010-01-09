#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Configure;
use Data::Dumper;
use Tsubaki::TermGroup;
use Tsubaki::QueryAnalyzer;
use Tsubaki::TermGroupCreater;
use Indexer;


my $CONFIG = Configure::get_instance();

push(@INC, $CONFIG->{SYNGRAPH_PM_PATH});

binmode (STDOUT, ':encoding(euc-jp)');
binmode (STDERR, ':encoding(euc-jp)');

&main();

sub main {
    require SynGraph;

    my $SYNGRAPH = new SynGraph($CONFIG->{SYNDB_PATH});
    # my $knpresult = $CONFIG->{KNP}->parse("水の中にもぐってするスポーツ");
    # my $knpresult = $CONFIG->{KNP}->parse("水の中に長時間もぐってするスポーツ");
    # my $knpresult = $CONFIG->{KNP}->parse("人工知能");
    my $knpresult = $CONFIG->{KNP}->parse("京都大学への行き方");
    # my $knpresult = $CONFIG->{KNP}->parse("京都大学");
    $knpresult->set_id(0);
    my $synresult = new KNP::Result($SYNGRAPH->OutputSynFormat($knpresult, $CONFIG->{SYNGRAPH_OPTION}, $CONFIG->{SYNGRAPH_OPTION}));

    # クエリ解析処理

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


    my $root = &Tsubaki::TermGroupCreater::create($synresult);
    print $root->to_S_exp() . "\n";
}
