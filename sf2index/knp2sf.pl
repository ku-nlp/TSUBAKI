#!/usr/bin/env perl

# $Id$

# usage: echo '温泉旅館に一番近い駅' | juman | knp -tab | perl knp2sf.pl
# usage: echo '温泉旅館に一番近い駅' | juman | knp -tab | perl -I/somewhere/SynGraph/perl /somewhere/SynGraph/scripts/knp_syn.pl -dbdir /somewhere/SynGraph/syndb/x86_64 -word_basic_unit | perl knp2sf.pl

use strict;
use utf8;
binmode(STDIN, ':encoding(euc-jp)');
binmode(STDOUT, ':encoding(utf8)');
use KNP::File;
use XML::LibXML;
use Encode;
use AddKNPResult;
use Getopt::Long;

my (%opt); GetOptions(\%opt, 'filter_fstring');

my $addknpresult = new AddKNPResult(\%opt);
my $knp = new KNP::File(file => $ARGV[0], encoding => 'euc-jp');
my $writer = new XML::LibXML::Document->new('1.0', 'utf-8');

my $sf_node = $writer->createElement('StandardFormat');
my $text_node = $writer->createElement('Text');

my $sentence_count = 0;
while (my $result = $knp->each()) {
    my $sentence_node = $writer->createElement('S');

    $sentence_count++;
    $sentence_node->setAttribute('id', $result->id ? $result->id : $sentence_count);

    my $rawstring = &get_rawstring($result);
    my $rawstring_node = $writer->createElement('RawString');
    $rawstring_node->appendText($rawstring);
    $sentence_node->appendChild($rawstring_node);

    # メイン
    my $annotation_node = $writer->createElement('Annotation');
    $addknpresult->Annotation2XML($writer, $result, $annotation_node);

    $sentence_node->appendChild($annotation_node);
    $text_node->appendChild($sentence_node);
}

$sf_node->appendChild($text_node);
$writer->setDocumentElement($sf_node);

my $string = $writer->toString(1); # 1 means indenting
print utf8::is_utf8($string) ? $string : decode('utf-8', $string);


# rawstringを得る
sub get_rawstring {
    my ($result) = @_;

    my $rawstring;

    for my $mrph ($result->mrph) {
	$rawstring .= $mrph->midasi;
    }

    return $rawstring;
}
