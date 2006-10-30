#!/usr/bin/env perl

# $Id$

###########################################################################
# JUMANの解析結果を読み込み、ドキュメントごとに単語頻度を計数するプログラム
###########################################################################

use strict;
# use encoding 'utf8';
use utf8;
use XML::DOM;
use Encode qw(decode encode from_to);
use Getopt::Long;
use Indexer qw(makeIndexfromJumanResult makeIndexfromKnpResult);

my (%opt); GetOptions(\%opt, 'in=s', 'out=s', 'direct', 'knp');

die "Option Error!\n" if (!$opt{in} || !$opt{out});

# 単語IDの初期化
my %freq;
my $parser = new XML::DOM::Parser unless ($opt{direct});
my $TAG_NAME = "Juman";
$TAG_NAME = "Knp" if($opt{knp});

# データのあるディレクトリを開く
opendir (DIR, $opt{in});

foreach my $ftmp (sort {$a <=> $b} readdir(DIR)) {
    undef %freq;
	
    # *.xmlを読み込む
    # 数字のみのファイルが対象
    next if ($ftmp !~ /(^0*)(\d+)\.xml$/);
    my $NAME = $1 . $2;
    my $SHORT_NAME = $2;

#   print STDERR "$NAME";
    
    # ファイルからJUMANの解析結果を読み込む
    open (FILE, '<:utf8', "$opt{in}/$ftmp") || die("no such file $ftmp\n");
    # Juman / Knpの解析結果を使ってインデックスを作成
    
    my $flag = 0;
    my $buff = '';
    while (<FILE>) {
	next if($_ =~ /^succeeded\.$/);
	    
	if($_ =~ /\<S.+ Id="(\d+)"\>/){
	    print STDERR "\rdir=$opt{in},file=$NAME (Id=$1)";
	}

	if($_ =~ /^\]\]\><\/$TAG_NAME>/){
#	    my $indexes = &Indexer::makeIndexfromKnpResult(encode('utf8',$buff));
	    my $indexes;
#	    my $temp = encode('euc-jp',$buff);
#	    print STDERR ">>> $temp\n";

	    if($opt{knp}){
		$indexes = &Indexer::makeIndexfromKnpResult($buff);
	    }else{
		$indexes = &Indexer::makeIndexfromJumanResult($buff);
	    }

	    foreach my $k (keys %{$indexes}){
		$freq{$k} += $indexes->{$k};
	    }
	    $buff = '';
	    $flag = 0;
 	    }elsif($_ =~ /.*\<$TAG_NAME\>\<\!\[CDATA\[/){
		$buff = "$'";
 		$flag = 1;
 	    }elsif($flag > 0){
		$buff .= "$_";
	    }
    }
    close FILE;

    # 単語IDと頻度のペアを出力
    open (OUT, '>:utf8', "$opt{out}/$NAME.idx");
    &Output(*OUT, $SHORT_NAME);
    close OUT;
    print STDERR " done.\n";
}
closedir(DIR);

sub read_sf {
    my ($doc) = @_;

    my $sentences = $doc->getElementsByTagName('S');
    for my $i (0 .. $sentences->getLength - 1) { # for each S
        my $sentence = $sentences->item($i);
        for my $s_child_node ($sentence->getChildNodes) {
            if ($s_child_node->getNodeName eq 'Juman') { # one of the children of S is Text
                for my $node ($s_child_node->getChildNodes) {
		    my $jmn = $node->getNodeValue;
		    for (split(/\n/, $jmn)) {
			&CountData($_);
		    }
                }
            }
        }
    }
}

sub CountData
{
    my ($input) = @_;
    return if ($input =~ /^(\<|\@|EOS)/);
    chomp $input;

    my @w = split(/\s+/, $input);

    # 削除する条件
    return if ($w[2] =~ /^[\s*　]*$/);
    return if ($w[3] eq "助詞");
    return if ($w[5] =~ /^(句|読)点$/);
    return if ($w[5] =~ /^空白$/);
    return if ($w[5] =~ /^(形式|副詞的)名詞$/);
    
    my $word = $w[2];
    if($input =~ /代表表記:(.+?)\//){
	$word = $1;
    }

    # 各単語IDの頻度を計数
#    $freq{$w[2]}++;
    $freq{$word}++;
}

sub Output
{
    my ($fh, $did) = @_;

    foreach my $wid (sort keys %freq) {
#	my $word = encode('euc-jp',$wid);
#	print STDERR "$word\n";
	print $fh "$wid $did:$freq{$wid}\n";
    }
}
