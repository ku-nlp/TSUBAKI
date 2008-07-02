#!/usr/bin/env perl

# $Id$

use strict;
use Juman;
use Encode;
use utf8;

binmode(STDOUT, ':utf8');


my @joshi = ('について', 'が', 'を');
my @explain = ('説明されている', '説明している', '説明してある', '説明された', '書かれている', '書いている', '書いてある', '書かれた', '記述されている', '記述している', '記述してある', '記述された', '記載されている', '記載している', '記載してある', '記載された', '述べられている', '述べている', '述べてある', '述べられた');
my @doc = ('文書', 'ページ', 'ウェブページ', 'ウェヴページ', 'ＷＥＢページ', '情報');
my @joshi2 = ('が', 'を');
my @yogen = ('知りたい', 'しりたい', '探したい', 'さがしたい', '探している', 'さがしている', '欲しい', 'ほしい', '調べたい', 'しらべたい');

my @sents = ();
foreach my $j (@joshi) {
    foreach my $y (@yogen) {
	push(@sents, $j . $y);
    }

    foreach my $e (@explain) {
	foreach my $d (@doc) {
	    foreach my $j2 (@joshi2) {
		foreach my $y (@yogen) {
		    push(@sents, $j . $e . $d . $j2 . $y)
		}
	    }
	}
    }
}


foreach my $d (@doc) {
    foreach my $j2 (@joshi2) {
	foreach my $y (@yogen) {
	    push(@sents, $d . $j2 . $y)
	}
    }
}


foreach my $y (@yogen) {
    push(@sents, $y);
}

my $rid = 1028;
# my $rid = 8388;
my $juman = new Juman();
foreach my $s (@sents) {
    my $result = $juman->analysis("Ｘ" . $s);
    my $rule;
    my @mrphs = $result->mrph;
    shift @mrphs;
    for (my $i = 0; $i < scalar(@mrphs) - 1; $i++) {
	my $m = $mrphs[$i];
	$rule .= sprintf("[%s * * * %s] ", $m->hinsi, $m->genkei);
    }
    my $m = $mrphs[-1];
    $rule .= sprintf("[%s * * * %s ((表現文末))] ", $m->hinsi, $m->genkei);

    print "; 〜$s<文末表現>\n";
    print "(\n";
    print "( ?* )\n";
    print "( $rule )\n";
    print "( ?* )\n";
    print "\tWhat-Search型 RID:$rid\n";
    print ")\n\n";

    $rid++;
}


my @q_exp = ('だれ', '誰', 'なに', '何', 'いつ', '何時', 'どれ', '何れ', 'どこ', '何処');
my @bunmatsu =  ('', 'ですか', 'でしょうか', 'でしょう', 'でしたか', 'でしたっけ', 'か');

foreach my $q (@q_exp) {
    foreach my $b (@bunmatsu) {
	my $s = "$q$b";

	my $result = $juman->analysis($s);
	my $rule;
	my @mrphs = $result->mrph;

	for (my $i = 0; $i < scalar(@mrphs) - 1; $i++) {
	    my $m = $mrphs[$i];
	    $rule .= sprintf("[%s * * * %s] ", $m->hinsi, $m->genkei);
	}
	my $m = $mrphs[-1];
	$rule .= sprintf("[%s * * * %s ((表現文末))] ", $m->hinsi, $m->genkei);

	print "; 〜$s<文末表現>\n";
	print "(\n";
	print "( ?* )\n";
	print "( $rule )\n";
	print "( ?* )\n";
	print "\tWhat-Search型 RID:$rid\n";
	print ")\n\n";

	$rid++;

	$rule .= sprintf("[* * * * ？]");
	print "; 〜$s<文末表現>？\n";
	print "(\n";
	print "( ?* )\n";
	print "( $rule )\n";
	print "( ?* )\n";
	print "\tWhat-Search型 RID:$rid\n";
	print ")\n\n";

	$rid++;
    }
}
