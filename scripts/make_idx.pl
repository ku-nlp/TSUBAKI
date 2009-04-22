#!/usr/bin/env perl

# $Id$

#########################################################################################
# JUMAN.KNP/SynGraphの解析結果を読み込み、ドキュメントごとに単語頻度を計数するプログラム
#########################################################################################

use strict;
use utf8;
use Encode;
use Getopt::Long;
use File::stat;
use Indexer;
use KNP::Result;
use StandardFormatData;
use Error qw(:try);
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
	   'ignore_syn_dpnd',
	   'ignore_hypernym',
	   'ignore_genkei',
	   'skip_large_file=s',
	   'max_num_of_indices=s',
	   'max_length_of_rawstring=s',
	   'genkei',
	   'scheme=s',
	   'title',
	   'keywords',
	   'description',
	   'inlinks',
	   'sentences',
	   'timeout=s',
	   'use_pm',
	   'verbose',
	   'help');


# デフォルト値の設定

# タイムアウトの設定(30秒)
$opt{timeout} = 30 unless ($opt{timeout});

# 指定がない場合は、標準フォーマットにSYNGRAPHの解析結果が埋め込まれていると見なす
$opt{scheme} = "SynGraph" unless ($opt{scheme});
$opt{ignore_syn_dpnd} = 0 unless ($opt{ignore_syn_dpnd});

if (!$opt{title} && !$opt{keywords} && !$opt{description} && !$opt{inlinks} && !$opt{sentences}) {
    # インデックス抽出対象が指定されていない場合は title, keywords, description, sentences を対象とする
    $opt{title} = 1;
    $opt{keywords} = 1;
    $opt{description} = 1;
    $opt{sentences} = 1;
}


if (!$opt{title} && !$opt{keywords} && !$opt{description} && $opt{inlinks} && !$opt{sentences}) {
    $opt{only_inlinks} = 1;
}



# 一文から抽出される索引表現数の上限
$opt{max_num_of_indices} = 10000 unless ($opt{max_num_of_indices});

# フレーズ検索のため、原形インデックスを作成（デフォルト）
$opt{ignore_genkei} = 0 unless ($opt{ignore_genkei});

# <RawString>タグの要素が5000byteを越える場合（文字化け・英数字の羅列など）はインデックス抽出を行わない
$opt{max_length_of_rawstring} = 5000 unless ($opt{max_length_of_rawstring});

my %CACHE = ();

&main();

sub usage {
    print "Usage perl $0 -in xmldir -out idxdir [-jmn|-knp|-syn] [-position] [-z] [-compress] [-file] [-scheme [Juman|Knp|SynGraph]] [-title] [-keywords] [-description] [-inlinks] [-sentences] [-verbose] [-help]\n";
    exit;
}

sub main {
    if (((!$opt{in} || !$opt{file}) && !$opt{out}) || $opt{help}) {
	&usage();
    }
    die "Not found! $opt{in}\n" unless (-e $opt{in} || -e $opt{file});

    if (!$opt{jmn} && !$opt{knp} && !$opt{syn}) {
	die "-jmn, -knp, -syn のいずれかを指定して下さい.\n";
    }

    if ($opt{jmn} + $opt{knp} + $opt{syn} > 1) {
	die "-jmn, -knp, -syn のうち一つを指定して下さい.\n";
    }


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

sub extract_indices_wo_pm {
    my ($file, $fid, $my_opt) = @_;

    my $indexer = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	without_using_repname => $opt{genkei} });

    my $indexer_genkei = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	genkei => 1 });

    if ($my_opt->{gzipped}) {
	open(READER, "zcat $file 2> /dev/null |");
    } else {
	open(READER, $file);
    }
    binmode(READER, ':utf8');


    my @buf;
    push(@buf, 'Title') if ($opt{title});
    push(@buf, 'Keywords') if ($opt{keywords});
    push(@buf, 'Description') if ($opt{description});
    push(@buf, 'InLink') if ($opt{inlinks});
    push(@buf, 'S') if ($opt{sentences});
    my $pattern = join("|", @buf);


    # Title, Keywords, Description, Inlink には文IDがないため、-100000からカウントする
    my $sid = -100000;
    my $isIndexingTarget = 0;
    my $tagName;
    my $content;
    my %indices = ();
    LOOP:
    while (<READER>) {
	last if ($_ =~ /<Text / && $opt{only_inlinks});

	if ($_ !~ /^(?:\s|\])/) {
	    $content .= $_ if ($isIndexingTarget);
	}
	elsif ($_ =~ /^\s*(<($pattern)(?: |\>).*\n)/o) {
	    $isIndexingTarget = 1;
	    $content = $1;
	    $tagName = $2;

	    if ($_ =~ /Length=\"(\d+)\"/) {
		my $length = $1;
		# $opt{max_length_of_rawstring}バイトより大きい場合は読み込まない, 越える場合は文字化け、英数字の羅列の可能性
		if ($length > $opt{max_length_of_rawstring}) {
		    my $rawstring = <READER>;
		    while (<READER>) {
			if (/(.*\<\/($pattern)\>)/o) {
			    $isIndexingTarget = 0;
			    $tagName = '';
			    $content = '';

			    next LOOP;
			}
		    }
		}
	    }

	    # 文IDの取得
	    if (/\<S.*? Id="(\d+)"/) {
		print STDERR "\rdir=$opt{in},file=$fid (Id=$1)" if ($opt{verbose});
		$sid = $1;
	    }
	    elsif (/\<(?:Title|InLink|Description|Keywords)/) {
		$sid += 2;
		print STDERR "\rdir=$opt{in},file=$fid (Id=$sid)" if ($opt{verbose});
	    }
 	}
 	elsif (/(.*\<\/($pattern)\>)/o) {
	    $content .= $1;

	    my $terms = &extractIndices($content, $indexer, $file, $indexer_genkei);

	    # インリンクの場合は披リンク数分を考慮する
	    if ($tagName eq 'InLink') {
		my $num_of_linked_pages = 0;
		while ($content =~ m!<DocID[^>]+>(NW)?\d+</DocID>!go) {
		    $num_of_linked_pages++;
		}

		foreach my $term (@$terms) {
		    $term->{score} *= $num_of_linked_pages;
		    $term->{freq} *= $num_of_linked_pages;
		}
	    }
	    $indices{$sid} = $terms if (defined $terms);

	    $isIndexingTarget = 0;
	    $tagName = '';
	    $content = '';
 	}
	else {
	    $content .= $_ if ($isIndexingTarget);
	}
    }
    close(READER);


    # 索引のマージ
    return &merge_indices(\%indices);
}



sub extractIndices {
    my ($content, $indexer, $file, $indexer_genkei) = @_;

    my ($annotation) = ($content =~ /<Annotation[^>]+?>\<\!\[CDATA\[((.|\n)+)\]\]\><\/Annotation>/);

    return if ($annotation eq '');

    my $knp_result;
    if ($opt{scheme} eq 'SynGraph') {
	# `空行 or !' or '#' ではじまる行はスキップ
	$knp_result = join ("\n", grep { $_ ne '' && $_ !~ /^(?:!|\#)/ } split ("\n", $annotation));
    } else {
	$knp_result = $annotation;
    }

    my $terms;
    if ($opt{syn}) {
	my @contentWordFeatures = ();
	my @buf;
	foreach my $line (split (/\n/, $knp_result)) {
	    next if ($line =~ /^\* /);

	    if ($line =~ /^\+ /) {
		if (scalar(@buf)) {
		    my $m = $buf[-1];
		    foreach my $mline (@buf) {
			if ($mline =~ /<内容語>/) {
			    $m = $mline;
			    last;
			}
		    }

		    if ($m =~ /((?:<[^<]+>)+)$/) {
			push (@contentWordFeatures, $1);
		    } else {
			print STDERR "\? $m\n";
		    }
		    @buf = ();
		}
	    } else {
		push (@buf, $line);
	    }
	}

# 	my $knp_result_obj = new KNP::Result($knp_result);
# 	foreach my $tag ($knp_result_obj->tag) {
# 	    my @mrphs = $tag->mrph;
# 	    my $m = $mrphs[-1];
# 	    foreach my $mrph (@mrphs) {
# 		print $mrph->fstring . "\n";
# 		if ($mrph->fstring =~ /<意味有|内容語>/) {
# 		    $m = $mrph;
# 		    last;
# 		}
# 	    }
# 	    push(@contentWordFeatures, $m);
# 	}

	my $terms_syn = $indexer->makeIndexfromSynGraph($annotation, \@contentWordFeatures, { max_num_of_indices => $opt{max_num_of_indices},
											      use_of_syngraph_dependency => !$opt{ignore_syn_dpnd},
											      use_of_hypernym => !$opt{ignore_hypernym},
											      use_of_negation_and_antonym => 1,
											      verbose => $opt{verbose}} );
	my ($rawstring) = ($content =~ m!<RawString>(.+?)</RawString>!);
	unless (defined $terms_syn) {
	    print STDERR "[SKIP] A large number of indices are extracted from [$rawstring]: $file (limit=" . $opt{max_num_of_indices} . ")\n";
	}

	# 出現形インデックスを抽出しマージする
	if (!$opt{ignore_genkei}) {
	    my $knp_result_obj = $CACHE{$rawstring};
	    unless ($knp_result_obj) {
		$knp_result_obj = new KNP::Result($knp_result);
		$CACHE{$rawstring} = $knp_result_obj;
	    }

	    my $terms_genkei = $indexer_genkei->makeIndexFromKNPResultObject($knp_result_obj);
	    push(@$terms, @$terms_genkei) if (defined $terms_genkei);
	    push(@$terms, @$terms_syn) if (defined $terms_syn);
	} else {
	    $terms = $terms_syn;
	}
    }
    elsif ($opt{knp}) {
	$terms = $indexer->makeIndexFromKNPResult($knp_result, \%opt);
    }
    else {
	$terms = $indexer->makeIndexfromJumanResult($annotation);
    }

    return $terms;
}

sub extract_indice_from_single_file {
    my ($file, $fid) = @_;

    # ファイルサイズのチェック
    if ($opt{skip_large_file}) {
	my $st = stat($file);
	return unless $st;

	if ($st->size > $opt{skip_large_file}) {
	    print STDERR "Too large file: $file (" . $st->size . " bytes > limit=$opt{skip_large_file} bytes)\n";
	    return;
	}
    }

    try {
	# タイムアウトの設定
	local $SIG{ALRM} = sub {die "timeout"};
	alarm $opt{timeout};

	# 索引表現の抽出
	my $indice;
	if ($opt{use_pm}) {
	    my $sfdat = new StandardFormatData($file, {gzipped => $opt{z}, is_old_version => 0});
	    $indice = &extract_indices($sfdat, $fid);
	} else {
	    $indice = &extract_indices_wo_pm($file, $fid, {gzipped => $opt{z}});
	}
	# 時間内に終了すればタイムアウトの設定を解除
	alarm 0;



	# 出力
	if ($opt{compress}) {
	    open(WRITER, "| gzip > $opt{out}/$fid.idx.gz");
	    binmode(WRITER, ':utf8');
	} else {
	    open(WRITER, '>:utf8', "$opt{out}/$fid.idx");
	}

	# NTCIRで提供されている文書の場合は、$fidから先頭のNWを削除
	$fid =~ s/^NW//;

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

    } catch Error with {
	printf STDERR (qq([WARNING] Time out occured! (time=%d [sec], file=%s)\n), $opt{timeout}, $file);
    };
}

# Juman / Knp / SynGraph の解析結果を使ってインデックスを作成
sub extract_indices {
    my ($sfdat, $fid) = @_;

    my $sid = -10000;
    my $contentFlag = 0;
    my $annotationFlag = 0;
    my $result;
    my $indexer = new Indexer({ignore_yomi => $opt{ignore_yomi},
			       without_using_repname => $opt{genkei}
			      });

    # オプションにしたがって各データフィールドから索引表現を抽出

    # Title, Keywords, Description, Inlink には文IDがないため、-100000からカウントする
    my $sid = -100000;

    my %indices = ();
    # Title, Keywords, Description はとなりあう文とは思わない
    $indices{$sid += 2} = &extract_indices_from_annotation($indexer, $sfdat->getTitle()) if ($opt{title});
    $indices{$sid += 2} = &extract_indices_from_annotation($indexer, $sfdat->getKeywords()) if ($opt{keywords});
    $indices{$sid += 2} = &extract_indices_from_annotation($indexer, $sfdat->getDescription()) if ($opt{description});

    if ($opt{inlinks}) {
	foreach my $inlink (@{$sfdat->getInlinks()}) {
	    my $num_of_pages = scalar(@{$inlink->{dids}});
	    my $terms = &extract_indices_from_annotation($indexer, $inlink);
	    foreach my $term (@$terms) {
		$term->{score} *= $num_of_pages;
		$term->{freq} *= $num_of_pages;
	    }
	    # Inlink はとなりあう文とは思わない
	    $indices{$sid += 2} = $terms;
	}
    }

    if ($opt{sentences}) {
	foreach my $s (@{$sfdat->getSentences()}) {
	    $indices{$s->{id}} = &extract_indices_from_annotation($indexer, $s);
	}
    }

    return &merge_indices(\%indices);
}

sub merge_indices {
    my ($indices) = @_;

    # 索引のマージ
    my %ret;
    foreach my $sid (sort {$a <=> $b} keys %$indices) {
	foreach my $index (@{$indices->{$sid}}) {
	    my $midasi = $index->{midasi};
	    next if ($midasi =~ /\->/ && $midasi =~ /s\d+/ && $opt{ignore_syn_dpnd});

	    print $midasi if ($opt{verbose});
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

# Juman / Knp / SynGraph の解析結果を使ってインデックスを作成
sub extract_indices_from_annotation {
    my ($indexer, $node) = @_;


    my $annotation = $node->{annotation};

    if ($opt{verbose}) {
	my $rawstring = $node->{rawstring};
	print $rawstring . "\n";
    }

    return if ($annotation eq '');

    my $indices;
    if ($opt{syn}) {
	if ($opt{scheme} eq 'SynGraph') {
	    $indices = $indexer->makeIndexfromSynGraph4Indexing($annotation);
	} else {
	    die "標準フォーマット内の解析結果と抽出したい索引表現のタイプが一致しません. (標準フォーマット: $opt{scheme}, 索引表現:SynGraph)\n";
	}
    }
    else {
	my $knp_result;
	if ($opt{scheme} eq 'SynGraph' && $opt{knp}) {
	    foreach my $line (split("\n", $annotation)) {
		# `!' ではじまる行はスキップ
		next if ($line =~ /^!/);

		$knp_result .= $line . "\n";
	    }
	} else {
	    $knp_result = $annotation;
	}

	if ($opt{knp}) {
	    $indices = $indexer->makeIndexFromKNPResult($knp_result, \%opt);
	}
	else {
	    $indices = $indexer->makeIndexfromJumanResult($knp_result);
	}
    }

    return $indices;
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
	next if ($midasi eq '' || $midasi =~ /^\->/ || $midasi =~ /\->$/);

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
