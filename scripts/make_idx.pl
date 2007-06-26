#!/usr/bin/env perl

# $Id$

#########################################################################################
# JUMAN.KNP/SynGraphの解析結果を読み込み、ドキュメントごとに単語頻度を計数するプログラム
#########################################################################################

use strict;
use utf8;
use Encode;
use Getopt::Long;
use Indexer;



my (%opt);
GetOptions(\%opt, 'in=s', 'out=s', 'jmn', 'knp', 'syn', 'position', 'z');

&main();

sub main {
    die "Option Error!\n" if (!$opt{in} || !$opt{out});
    die "Not found! $opt{in}\n" unless (-e $opt{in});
    die "Not found! $opt{out}\n" unless (-e $opt{out});
    
    # 単語IDの初期化
    my $TAG_NAME = "Juman";
    $TAG_NAME = "Knp" if ($opt{knp});

    if ($opt{syn}) {
	$TAG_NAME = "SynGraph";
	# SynGraph インデックスではposition, sentenceは考慮しない
	$opt{position} = 0;
	$opt{sentence} = 0;
    }

    # データのあるディレクトリを開く
    opendir (DIR, $opt{in}) or die;
    foreach my $file (sort {$a <=> $b} readdir(DIR)) {
	# *.xmlを読み込む
	# 数字のみのファイルが対象
	next if ($file !~ /(^\d+)\.xml/);
	
	my $fid = $1;
	if ($opt{z}) {
	    open(READER, "zcat $opt{in}/$file |") || die ("No such file $opt{in}/$file\n");
	    binmode(READER, ':utf8');
	} else {
	    open(READER, '<:utf8', "$opt{in}/$file") || die ("No such file $file\n");
	}
	
	# Juman / Knp / SynGraph の解析結果を使ってインデックスを作成
	my $sid = 0;
	my $flag = 0;
	my $result;
	my %indice;
	my $indexer = new Indexer();
	while (<READER>) {
	    if (/\<S.*? Id="(\d+)"/) {
		print STDERR "\rdir=$opt{in},file=$fid (Id=$1)";
		$sid = $1;
	    }
	    
	    if (/^\]\]\><\/Annotation>/) {
#		$result = decode('utf8', $result) unless (utf8::is_utf8($result));
		
		my $idxs;
		if ($opt{knp}) {
		    $idxs = $indexer->makeIndexfromKnpResult($result);
		} elsif($opt{syn}) {
		    $idxs = $indexer->makeIndexfromSynGraph($result);
		} else {
		    $idxs = $indexer->makeIndexfromJumanResult($result);
		}
		
		foreach my $k (keys %{$idxs}) {
		    $indice{$k}->{freq} += $idxs->{$k}{freq};
		    if ($opt{position}) {
			push(@{$indice{$k}->{sids}}, $sid);
			push(@{$indice{$k}->{poss}}, @{$idxs->{$k}{absolute_pos}});
		    }
		}
		$result = undef;
		$flag = 0;
	    } elsif (/.*\<Annotation Scheme=\"$TAG_NAME\"\>\<\!\[CDATA\[/) {
		$result = "$'";
		$flag = 1;
	    } elsif($flag > 0) {
		$result .= $_;
	    }
	}
	close(READER);


	my $fid_short = $fid + 0;
	# 単語IDと頻度のペアを出力
	open(WRITER, '>:utf8', "$opt{out}/$fid.idx");
	if ($opt{position}) {
	    &output_with_position(*WRITER, $fid_short, \%indice);
	} else {
	    &output_wo_position(*WRITER, $fid_short, \%indice);
	}
	close(WRITER);
	print STDERR " done.\n";
    }
    closedir(DIR);
}

sub output_with_position {
    my ($fh, $did, $indice) = @_;

    foreach my $k (sort {$a cmp $b} keys %{$indice}) {
	my $freq = $indice->{$k}{freq};
	my $sid_str = join(',', @{$indice->{$k}{sids}});
	my $pos_str = join(',', @{$indice->{$k}{poss}});

	if ($freq == int($freq)) {
	    printf $fh ("%s %d:%s@%s#%s\n", $k, $did, $freq, $sid_str, $pos_str);
	} else {
	    if ($freq =~ /\.\d{4,}$/) {
		printf $fh ("%s %d:%.4f@%s#%s\n", $k, $did, $freq, $sid_str, $pos_str);
	    } else {
		printf $fh ("%s %d:%s@%s#%s\n", $k, $did, $freq, $sid_str, $pos_str);
	    }
	}
    }
}

sub output_wo_position {
    my ($fh, $did, $indice) = @_;

    foreach my $k (sort {$a cmp $b} keys %{$indice}) {
	my $freq = $indice->{$k}{freq};

	if ($freq == int($freq)) {
	    printf $fh ("%s %d:%s\n", $k, $did, $freq);
	} else {
	    if ($freq =~ /\.\d{4,}$/) {
		printf $fh ("%s %d:%.4f\n", $k, $did, $freq);
	    } else {
		printf $fh ("%s %d:%s\n", $k, $did, $freq);
	    }
	}
    }
}
