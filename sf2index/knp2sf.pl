#!/usr/bin/env perl

# $Id$

# usage: echo '温泉旅館に一番近い駅' | juman | knp -tab | perl knp2sf.pl
# usage: echo '温泉旅館に一番近い駅' | juman | knp -tab | perl -I/somewhere/SynGraph/perl /somewhere/SynGraph/scripts/knp_syn.pl -dbdir /somewhere/SynGraph/syndb/x86_64 perl knp2sf.pl

use strict;
use utf8;
binmode(STDIN, ':encoding(euc-jp)');
binmode(STDOUT, ':encoding(utf8)');
use KNP::File;
use XML::Writer;
use Getopt::Long;

my (%opt); GetOptions(\%opt, 'filter_fstring');

my %pf_order = (id => 0, dpnd => 1, cat => 2, f => 3); # print order of phrase attributes
my %wf_order = (id => 0, lem => 1, read => 2, pos => 3, repname => 4, conj => 5, f => 99); # print order of word attributes
my %synnodesf_order = (dpnd => 0, phraseid => 1);
my %synnodef_order = (synid => 0, score => 1);

my $knp = new KNP::File(file => $ARGV[0], encoding => 'euc-jp');
my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);

$writer->xmlDecl('utf-8');
$writer->startTag('StandardFormat');
$writer->startTag('Text');

my $old_id = '';
my $sentence_count = 0;

while (my $result = $knp->each()) {
    my ($prob) = ($result->comment =~ /SCORE:([\-\d\.]+)/);

    $sentence_count++;
    $writer->startTag('S', id => $result->id ? $result->id : $sentence_count);

    my $rawstring = &get_rawstring($result);
    $writer->startTag('Rawstring');
    $writer->characters($rawstring);
    $writer->endTag();

    my $version = $result->version;
    $writer->startTag('AnnotationTool', tool => "KNP:$version");
    $writer->startTag('result', score => $prob);
    
    my $abs_wnum = 0;
    my $pnum = 0;

    for my $bnst ($result->bnst) {
	my @tags = $bnst->tag_list;
	my $bnst_end_pnum = $pnum + @tags - 1;
	for my $tag_num (0 .. @tags - 1) {
	    my $bnst_start_flag = 1 if $tag_num == 0;
	    my $tag = $tags[$tag_num];
	    my (%pf);

	    $pf{id} = $pnum;

	    # 係り先
	    if ($tag->parent) {
		$pf{dpnd} = $tag->parent->id;
	    }
	    else {
		$pf{dpnd} = -1;
	    }

	    # feature processing
	    my $fstring = $tag->fstring;

	    # phrase category
	    # 判定詞は 用言:判
	    if ($fstring =~ s/<(用言[^>]*)>//) {
		$pf{cat} = $1;
	    }
	    elsif ($fstring =~ s/<(体言[^>]*)>//) {
		$pf{cat} = $1;
	    }
	    else {
		$pf{cat} = 'NONE';
	    }

	    # feature残り
	    $pf{f} = $opt{filter_fstring} ? &filter_fstring($fstring) : $fstring;

	    # 文節
	    $pf{f} .= sprintf("<文節:%d-%d>", $pnum, $bnst_end_pnum) if $bnst_start_flag;

	    $pf{f} .= '...';

	    $writer->startTag('phrase', map({$_ => $pf{$_}} sort {$pf_order{$a} <=> $pf_order{$b}} keys %pf));

	    # synnodes
	    for my $synnodes ($tag->synnodes) {
		my %synnodes_f;
		$synnodes_f{dpnd} = $synnodes->parent;
		$synnodes_f{phraseid} = $synnodes->tagid;

		$writer->startTag('synnodes', map({$_ => $synnodes_f{$_}} sort {$synnodesf_order{$a} <=> $synnodesf_order{$b}} keys %synnodes_f));

 		for my $synnode ($synnodes->synnode) {
		    my %synnode_f;
		    $synnode_f{synid} = $synnode->synid;
		    $synnode_f{score} = $synnode->score;

		    $writer->emptyTag('synnode', map({$_ => $synnode_f{$_}} sort {$synnodef_order{$a} <=> $synnodef_order{$b}} keys %synnode_f));
 		}
		$writer->endTag();
	    }

	    # word
	    for my $mrph ($tag->mrph) {

		$fstring = $mrph->fstring;

		# 代表表記
		my $rep;
		if ($fstring =~ /<代表表記:([^\s\"\>]+)/) {
		    $rep = $1;
		}
		elsif ($fstring =~ /<疑似代表表記:([^\s\"\>]+)/) {
		    $rep = $1;
		}
		else {
		    # $lem = $mrph->genkei . '/' . $mrph->yomi;
		    $rep = $mrph->genkei . '/' . $mrph->genkei;
		}

		# 活用
		my $conj;
		if ($mrph->katuyou1 ne '*') {
		    $conj = $mrph->katuyou1 . ':' . $mrph->katuyou2;
		}
		else {
		    $conj = '';
		}

		my %wf = (lem => $mrph->genkei,
			  read => $mrph->yomi,
			  repname => $rep, 
			  pos => $mrph->hinsi,
			  conj => $conj,
			  id => $abs_wnum,
			 );
		$wf{pos} .= ':' . $mrph->bunrui if ($mrph->bunrui ne '*');

		$wf{f} = $opt{filter_fstring} ? &filter_fstring($fstring) . '...' : $fstring;

		$writer->startTag('word', map({$_ => $wf{$_}} sort {$wf_order{$a} <=> $wf_order{$b}} keys %wf));
		$writer->characters($mrph->midasi);
		$writer->endTag();
		$abs_wnum++;
	    }
	    $writer->endTag();		# phrase
	    $pnum++;
	}
    }
    $writer->endTag(); # result
    $writer->endTag(); # AnnotationTool
    $writer->endTag(); # S
}

$writer->endTag(); # Text
$writer->endTag(); # StandardFormat
$writer->end();

sub filter_fstring {
    my ($str) = @_;

    my (@f);
    if ($str =~ /(<係:[^>]+>)/) {
	push(@f, $1);
    }
    elsif ($str =~ /(<(?:自立|接頭|付属|内容語|準内容語)>)/) {
	push(@f, $1);
    }

    return join('', @f);
}

# rawstringを得る
sub get_rawstring {
    my ($result) = @_;

    my $rawstring;

    for my $mrph ($result->mrph) {
	$rawstring .= $mrph->midasi;
    }

    return $rawstring;
}
