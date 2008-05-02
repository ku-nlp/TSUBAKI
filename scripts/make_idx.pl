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
use KNP::Result;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

binmode(STDOUT, ":encoding(euc-jp)");
binmode(STDERR, ":encoding(euc-jp)");


my (%opt);
GetOptions(\%opt,
	   'in=s',
	   'out=s',
	   'jmn',
	   'knp',
	   'syn',
	   'position',
	   'z',
	   'compress',
	   'file=s',
	   'ignore_yomi',
	   'genkei',
	   'scheme=s',
	   'extract_from_only_inlink',
	   'verbose',
	   'help');

$opt{scheme} = "Knp" unless ($opt{scheme});
$opt{extract_from} = "(?:Title|Description|Keywords|S)";
$opt{extract_from} = "InLink" if ($opt{extract_from_only_inlink});

&main();

sub usage {
    print "Usage perl $0 -in xmldir -out idxdir [-jmn|-knp|-syn] [-position] [-z] [-compress] [-file] [-scheme [Juman|Knp|SynGraph]] [-extract_from_only_inlink] [-verbose]\n";
    exit;
}

sub main {
    if (((!$opt{in} || !$opt{file}) && !$opt{out}) || $opt{help}) {
	&usage();
    }
    die "Not found! $opt{in}\n" unless (-e $opt{in} || -e $opt{file});
    unless (-e $opt{out}) {
	print STDERR "Create directory: $opt{out}\n";
	mkdir $opt{out};
    }
    
    if ($opt{file}) {
	die "Not xml file.\n" if ($opt{file} !~ /([^\/]+)\.xml/);
	&extract_indice_from_single_file($opt{file}, $1);
    }
    elsif ($opt{in}) {
	# データのあるディレクトリを開く
	opendir (DIR, $opt{in}) or die;
	foreach my $file (sort {$a <=> $b} readdir(DIR)) {
	    next unless ($file =~ /([^\/]+)\.xml/);
	    &extract_indice_from_single_file("$opt{in}/$file", $1);
	}
	closedir(DIR);
    }
}

sub extract_indice_from_single_file {
    my ($file, $fid) = @_;

    if ($opt{z}) {
	open(READER, "zcat $file |") || die ("No such file $file\n");
	binmode(READER, ':utf8');
    } else {
	open(READER, '<:utf8', "$file") || die ("No such file $file\n");
    }


    my $indice = &extract_indice(*READER, $fid);
    close(READER);

    if ($opt{compress}) {
	open(WRITER, "| gzip > $opt{out}/$fid.idx.gz");
	binmode(WRITER, ':utf8');
    } else {
	open(WRITER, '>:utf8', "$opt{out}/$fid.idx");
    }

    if ($opt{position}) {
	if ($opt{syn}) {
	    &output_syngraph_indice_with_position(*WRITER, $fid, $indice);
	} else {
	    &output_with_position(*WRITER, $fid, $indice);
	}
    } else {
	if ($opt{syn}) {
	    &output_syngraph_indice_wo_position(*WRITER, $fid, $indice);
	} else {
	    &output_wo_position(*WRITER, $fid, $indice);
	}
    }
    close(WRITER);
    print STDERR " done.\n" if ($opt{verbose});
}

# Juman / Knp / SynGraph の解析結果を使ってインデックスを作成
sub extract_indice {	
    my ($READER, $fid) = @_;

    my $sid = -10000;
    my $contentFlag = 0;
    my $annotationFlag = 0;
    my $result;
    my %indice = ();
    my $indexer = new Indexer({ignore_yomi => $opt{ignore_yomi},
			      without_using_repname => $opt{genkei}
			      });
    while (<$READER>) {
	if (/\<$opt{extract_from}( |\>)/) {
	    $contentFlag = 1;
	}
	elsif (/\<\/$opt{extract_from}\>/) {
	    $contentFlag = 0;
	}

	if (/\<S.*? Id="(\d+)"/) {
	    print STDERR "\rdir=$opt{in},file=$fid (Id=$1)" if ($opt{verbose});
	    $sid = $1;
	}
	elsif (/\<(?:Title|InLink|OutLink|Description|Keywords)/) {
	    $sid++;
	    print STDERR "\rdir=$opt{in},file=$fid (Id=$sid)" if ($opt{verbose});
	}


	if (/^\]\]\><\/Annotation>/) {
	    unless ($result =~ /^\n*$/) {
		if ($opt{syn}) {
		    $indice{$sid} = $indexer->makeIndexfromSynGraph4Indexing($result);
		}
		elsif ($opt{knp}) {
		    $indice{$sid} = $indexer->makeIndexFromKNPResult($result, \%opt);
		}
		else {
		    $indice{$sid} = $indexer->makeIndexfromJumanResult($result);
		}
	    }

	    $result = undef;
	    $annotationFlag = 0;
	} elsif (/.*\<Annotation Scheme=\"$opt{scheme}\"\>\<\!\[CDATA\[/) {
	    my $line = "$'";
	    $result = $line unless ($line =~ /^#/);
	    $annotationFlag = 1;
	} elsif ($annotationFlag && $contentFlag) {
	    next if ($_ =~ /^\#/);
	    # 標準フォーマット内の解析結果が SynGraph かつ $opt{knp} ならば `!' ではじまる行はスキップ
	    if ($opt{scheme} eq 'SynGraph' && $opt{knp}) {
		next if ($_ =~ /^!/);
	    }
	    $result .= $_;
	}
    }

    # 索引のマージ
    my %ret;
    foreach my $sid (sort {$a <=> $b} keys %indice) {
	foreach my $index (@{$indice{$sid}}) {
	    my $midasi = $index->{midasi};
	    $ret{$midasi}->{sids}{$sid} = 1;
	    if ($opt{syn}) {
		push(@{$ret{$midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score}});
		$ret{$midasi}->{score} += $index->{score};
	    } else {
		push(@{$ret{$midasi}->{poss}}, @{$index->{absolute_pos}});
		$ret{$midasi}->{freq} += $index->{freq};
	    }
	}
    }

    return \%ret;
}

sub output_syngraph_indice_wo_position {
    my ($fh, $did, $indice) = @_;

    foreach my $midasi (sort {$a cmp $b} keys %$indice) {
	my $score = &round($indice->{$midasi}{score});
	printf $fh ("%s %d:%s\n", $midasi, $did, $score);
    }
}


sub output_syngraph_indice_with_position {
    my ($fh, $did, $indice) = @_;

    foreach my $midasi (sort {$a cmp $b} keys %$indice) {
	my $score = &round($indice->{$midasi}{score});
	my $sids_str = join(',', sort {$a <=> $b} keys %{$indice->{$midasi}{sids}});
	my $pos_scr_str;
	foreach my $pos_score (sort {$a->{pos} <=> $b->{pos}} @{$indice->{$midasi}{pos_score}}) {
	    my $pos = $pos_score->{pos};
	    my $scr = &round($pos_score->{score});
	    $pos_scr_str .= $pos . "&" . $scr . ",";
	}
	chop($pos_scr_str);

	printf $fh ("%s %d:%s@%s#%s\n", $midasi, $did, $score, $sids_str, $pos_scr_str);
    }
}

sub output_with_position {
    my ($fh, $did, $indice) = @_;

    foreach my $midasi (sort {$a cmp $b} keys %{$indice}) {
	my $freq = $indice->{$midasi}{freq};
	my $sid_str = join(',', sort {$a <=> $b} keys %{$indice->{$midasi}{sids}});
	my $pos_str = join(',', @{$indice->{$midasi}{poss}});

	if ($freq == int($freq)) {
	    printf $fh ("%s %d:%s@%s#%s\n", $midasi, $did, $freq, $sid_str, $pos_str);
	} else {
	    if ($freq =~ /\.\d{4,}$/) {
		printf $fh ("%s %d:%.4f@%s#%s\n", $midasi, $did, $freq, $sid_str, $pos_str);
	    } else {
		printf $fh ("%s %d:%s@%s#%s\n", $midasi, $did, $freq, $sid_str, $pos_str);
	    }
	}
    }
}

sub output_wo_position {
    my ($fh, $did, $indice) = @_;

    foreach my $midasi (sort {$a cmp $b} keys %{$indice}) {
	my $freq = $indice->{$midasi}{freq};

	if ($freq == int($freq)) {
	    printf $fh ("%s %d:%s\n", $midasi, $did, $freq);
	} else {
	    if ($freq =~ /\.\d{4,}$/) {
		printf $fh ("%s %d:%.4f\n", $midasi, $did, $freq);
	    } else {
		printf $fh ("%s %d:%s\n", $midasi, $did, $freq);
	    }
	}
    }
}

sub round {
    my ($value) = @_;

    if ($value == int($value)) {
	$value = sprintf("%s", $value);
    } else {
	if ($value =~ /\.\d{4,}$/) {
	    $value = sprintf("%.4f", $value);
	} else {
	    $value = sprintf("%s", $value);
	}
    }

    return $value;
}
