#!/usr/bin/env perl

# $Id$

################################################
# 標準フォーマットから term を抽出するプログラム
################################################

# perl -I $HOME/cvs/Utils/perl make_idx.pl -in s -out i -syn -z -ignore_syn_dpnd -position -penalty -syngraph_dir SYNGRAPH_DIR

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

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");


my (%opt);
GetOptions(\%opt,
	   'in=s',
	   'out=s',
	   'jmn',
	   'knp',
	   'syn',
	   'logfile=s',
	   'position',
	   'z',
	   'compress',
	   'offset=s',
	   'file=s',
	   'infiles=s',
	   'outdir_prefix=s',
	   'ignore_yomi',
	   'ignore_syn_dpnd',
	   'ignore_hypernym',
	   'ignore_genkei',
	   'skip_large_file=s',
	   'max_num_of_indices=s',
	   'max_length_of_rawstring=s',
	   'genkei',
	   'english',
	   'scheme=s',
	   'title',
	   'keywords',
	   'description',
	   'inlinks',
	   'sentences',
	   'timeout=s',
	   'use_pm',
	   'use_block_type',
	   'ipsj',
	   'syngraph_dir=s',
	   'penalty',
	   'data_dir=s',
	   'feature=s',
	   'verbose',
	   'help');

##############################################
# ペナルティターム作成に利用するデータをロード
##############################################

my $ECTS;
my %SYNDB;
my %HYPODB;
if ($opt{penalty}) {
    require ECTS;
    my %_opt;
    my $_DATA_DIR            = (($opt{data_dir}) ? $opt{data_dir} : '../data');
    $_opt{bin_file}          = "$_DATA_DIR/ecs.db";
    $_opt{triedb}            = "$_DATA_DIR/offset.db";
    $_opt{term2id}           = "$_DATA_DIR/term2id";
    $_opt{size_of_on_memory} = 1000000000;
    $ECTS = new ECTS(\%_opt);

    # load syndb
    my $syndb = sprintf ("%s/syndb/%s/syndb.cdb", $opt{syngraph_dir}, (POSIX::uname())[4]);
    require CDB_File;
    tie my %_SYNDB, 'CDB_File', $syndb or die "$!($syndb)";
    while (my ($synid, $members) = each %_SYNDB) {
	my $_synid = decode('utf8', $synid);
	foreach my $string (split(/\|/, decode('utf8', $members))) {
	    # リソース情報を削除
	    $string =~ s!\[.+\]$!!;
	    # 読みを削除
	    $string =~ s!^(.+?)/.+$!\1!;

	    push (@{$SYNDB{$_synid}}, $string);
	}
    }

    # load hyponymy relation
    foreach my $isa_file ((sprintf ("%s/dic/rsk_iwanami/isa.txt.filtered.manual", $opt{syngraph_dir}),
			   sprintf ("%s/dic/wikipedia/isa.txt", $opt{syngraph_dir}))) {
	open (F, '<:encoding(euc-jp)', $isa_file) or die $!;
	while (<F>) {
	    my ($hyponym, $hypernym, $num) = split (/ /, $_);
	    $hyponym  =~ s!/.+$!!;
	    $hypernym =~ s!/.+$!!;
	    push (@{$HYPODB{$hypernym}}, $hyponym);
	}
	close (F);
    }
}

####################
# デフォルト値の設定
####################

# 同位語をもとに係り受けタームを作成する際の閾値
my $DIST_FOR_MAKING_COORD_DPND = 100;

# タイムアウトの設定(30秒)
$opt{timeout} = 30 unless ($opt{timeout});

# 指定がない場合は、標準フォーマットにSYNGRAPHの解析結果が埋め込まれていると見なす
$opt{scheme} = "SynGraph" unless ($opt{scheme});
$opt{ignore_syn_dpnd} = 0 unless ($opt{ignore_syn_dpnd});

# regexp for inlink counting
our $INLINK_PATTERN = qr/<DocID[^>]+>(?:NW)?\d+<\/DocID>/o;


###################################
# BlockTypeとプレフィックスのマップ
###################################

my %prefixOfBlockType;
$prefixOfBlockType{header}          = 'HD';
$prefixOfBlockType{footer}          = 'FT';
$prefixOfBlockType{link}            = 'LK';
$prefixOfBlockType{img}             = 'IM';
$prefixOfBlockType{form}            = 'FM';
$prefixOfBlockType{maintext}        = 'MT';
$prefixOfBlockType{unknown_block}   = 'UB';
$prefixOfBlockType{title}           = 'TT';
$prefixOfBlockType{keyword}         = 'KW';
$prefixOfBlockType{description}     = 'DS';
$prefixOfBlockType{inlink}          = 'AC';

# 論文検索
$prefixOfBlockType{author}          = 'AU';
$prefixOfBlockType{abstract}        = 'AB';
$prefixOfBlockType{acknowledgement} = 'AK';
$prefixOfBlockType{reference}       = 'RF';

# KUHP
$prefixOfBlockType{findings}        = 'FD';
$prefixOfBlockType{order}           = 'OD';
$prefixOfBlockType{imp}             = 'IP';



# istvan tags ver.1
my %prefixOfStringType;
$prefixOfStringType{AIM}            = 'AM';
$prefixOfStringType{BASE}           = 'BS';
$prefixOfStringType{PROPOSAL}       = 'PP';
$prefixOfStringType{PROBLEM}        = 'PB';

# istvan tags ver.2
$prefixOfStringType{CONTENT}        = 'CT';
$prefixOfStringType{CONTEXT}        = 'CX';
$prefixOfStringType{FOCUS}          = 'FC';
$prefixOfStringType{RELBASE}        = 'RB';
$prefixOfStringType{RESULT}         = 'RT';


my @ISTVAN_TAGS = (
		   'AIM',
		   'BASE',
		   'CONTENT',
		   'CONTEXT',
		   'FOCUS',
		   'PROBLEM',
		   'PROPOSAL',
		   'RELBASE',
		   'RESULT'
		   );


if (!$opt{title} && !$opt{keywords} && !$opt{description} && !$opt{inlinks} && !$opt{sentences} && !$opt{ipsj}) {
    # インデックス抽出対象が指定されていない場合は title, keywords, description, sentences を対象とする
    $opt{title} = 1;
    $opt{keywords} = 1;
    $opt{description} = 1;
    $opt{sentences} = 1;
}

if ($opt{ipsj}) {
    $opt{title} = 1;
    $opt{sentences} = 1;
    $opt{keyword} = 1;
    $opt{author} = 1;
    $opt{abstract} = 1;
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


# ブロックタイプの素性ビットを読み込む
my %BLOCK_TYPE2FEATURE = ();
if ($opt{feature}) {
    open (F, '<:utf8', $opt{feature}) or die $!;
    while (<F>) {
	next if ($_ =~ /^\#/);
	chop;
	my @data = split (/ /, $_);
	$BLOCK_TYPE2FEATURE{$data[2]} = $data[5];
    }
    $BLOCK_TYPE2FEATURE{""} = 0;
    close (F);
}

my %alreadyAnalyzedFiles = ();
if (-f $opt{logfile}) {
    open(LOG, $opt{logfile}) or die $!;
    while (<LOG>) {
	chomp;

	my ($file, $status) = split(/ /, $_);
	if ($status =~ /(success|error|timeout|large_file)/) {
	    $alreadyAnalyzedFiles{$file} = $status;
	}
	# ログのフォーマットにマッチしない = エラーにより終了
	else {
	    $alreadyAnalyzedFiles{$file} = "error";
	}
    }
    close(LOG);

    # ログフォーマットを整形して出力
    open(LOG, "> $opt{logfile}") or die $!;
    foreach my $file (sort {$a cmp $b} keys %alreadyAnalyzedFiles) {
	my $status = $alreadyAnalyzedFiles{$file};
	print LOG "$file $status\n";
    }
    close(LOG);
}


open(LOG, ">> $opt{logfile}") or die "$!\n" if ($opt{logfile});
open(SID2TID, ">> $opt{in}.sid2tid") or die "$!\n" if ($opt{offset});

&main();

if ($opt{logfile}) {
    print LOG "finish.\n";
    close(LOG);
}

close(SID2TID) if ($opt{offset});


sub usage {
    print "Usage perl $0 -in xmldir -out idxdir [-jmn|-knp|-syn] [-position] [-z] [-compress] [-file] [-scheme [Juman|Knp|SynGraph]] [-title] [-keywords] [-description] [-inlinks] [-sentences] [-verbose] [-help]\n";
    exit;
}

sub main {
    my $show_usage = 1;

    $show_usage = 0 if (($opt{file} || $opt{in}) && $opt{out});
    $show_usage = 0 if ($opt{infiles} && $opt{outdir_prefix});
    &usage() if ($show_usage);

    die "Not found! $opt{in}\n" unless (-e $opt{in} || -e $opt{file} || -e $opt{infiles});

    if (!$opt{jmn} && !$opt{knp} && !$opt{syn} && !$opt{english}) {
	die "-jmn, -knp, -syn, -english のいずれかを指定して下さい.\n";
    }

    if ($opt{jmn} + $opt{knp} + $opt{syn} + $opt{english} > 1) {
	die "-jmn, -knp, -syn, -english のうち一つを指定して下さい.\n";
    }


    if (defined $opt{out} && !-e $opt{out}) {
	print STDERR "Create directory: $opt{out}\n";
	mkdir $opt{out};
    }

    if ($opt{file}) {
	die "Not xml file.\n" if ($opt{file} !~ /([^\/]+?)(\.link)?\.xml/);
	&extract_indice_from_single_file($opt{file}, $1);
    }
    elsif ($opt{infiles}) {
	# インデキシング対象のファイルと出力先が記述されたファイルを開く
	open (FILE, $opt{infiles}) or die "$!";
	while (<FILE>) {
	    chop;
	    my $file = $_;
	    next unless ($file =~ /([^\/]+?)(\.link)?\.xml/);
	    my $fname = $1;
	    my ($fid, $version) = split (/\-/, $fname);
	    $opt{out} = sprintf (qq(%s/i%04d/i%07d), $opt{outdir_prefix}, $fid / 1000000, $fid / 1000);
	    `mkdir -p $opt{out}` unless (-e $opt{out});
	    &extract_indice_from_single_file($file, $fname);
	    $ECTS->clear() if ($opt{penalty});
	}
	close (FILE);
    }
    elsif ($opt{in}) {
	# データのあるディレクトリを開く
	opendir (DIR, $opt{in}) or die;
	my $fid = $opt{offset};
	foreach my $file (sort {$a <=> $b} readdir(DIR)) {
	    next if ($file eq '.' || $file eq '..');

	    if (defined $opt{offset}) {
		&extract_indice_from_single_file("$opt{in}/$file", sprintf ("%09d", $fid++));
	    } else {
		next unless ($file =~ /([^\/]+?)(\.link)?\.xml/);
		&extract_indice_from_single_file("$opt{in}/$file", $1);
	    }
	    $ECTS->clear() if ($opt{penalty});
	}
	closedir(DIR);
    }
}

sub extract_indices_wo_pm {
    my ($file, $fid, $my_opt) = @_;

    my $indexer = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	MAX_NUM_OF_TERMS_FROM_SENTENCE => $opt{max_num_of_indices},
	without_using_repname => $opt{genkei} });

    my $indexer_genkei = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	MAX_NUM_OF_TERMS_FROM_SENTENCE => $opt{max_num_of_indices},
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
    push(@buf, 'Keywords') if ($opt{keyword});
    push(@buf, 'Keyword') if ($opt{keyword});
    push(@buf, 'Authors') if ($opt{author});
    push(@buf, 'Author') if ($opt{author});
    push(@buf, 'Abstract') if ($opt{abstract});


    my $pattern = join("|", @buf);
    my $pattern_start = qr/^\s*(<($pattern)(?: |\>).*\n)/o;
    my $pattern_end   = qr/^(.*\<\/($pattern)\>)/o;

    # Title, Keywords, Description, Inlink には文IDがないため、-100000からカウントする
    my $sid;
    my $meta_sid = -100000;
    my $isIndexingTarget = 0;
    my $tagName;
    my $content;
    my %indices = ();
    my $rawstring;
    my %sid2blockType = ();
    my %results_of_istvan = ();
    my $blockType;
    my %pos2synnode = ();
    my %pos2info = ();
    LOOP:
    while (<READER>) {
	last if ($_ =~ /<Text / && $opt{only_inlinks});

	if ($_ =~ /<RawString>([^<]+?)<\/RawString>/) {
	    $rawstring = $1;
	}

	if ($_ !~ /^(?:\s|\])/) {
	    if ($isIndexingTarget) {
		$content .= $_;
	    }
	}
	elsif ($_ =~ $pattern_start) {
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

	    # 領域判定結果の取得
	    $blockType = 'unknown_block' unless ($opt{ipsj});
	    if ($tagName eq 'Title') {
		$blockType = 'title';
	    }
	    elsif ($tagName eq 'Description') {
		$blockType = 'description';
	    }
	    elsif ($tagName eq 'Keywords') {
		$blockType = 'keyword';
	    }
	    elsif (/\<.*? BlockType="(.+?)"/) {
		$blockType = $1;
	    }

	    # 文IDの取得
	    if (/\<S.*? Id="(\d+)"/ && $blockType ne 'abstract') {
		print STDERR "\rdir=$opt{in},file=$fid (Id=$1)" if ($opt{verbose});
		$sid = $1;
	    }
	    elsif (/\<(?:$pattern)/) {
		$meta_sid += 2;
		$sid = $meta_sid;
		print STDERR "\rdir=$opt{in},file=$fid (Id=$sid)" if ($opt{verbose});
	    }


	    # istvan's result を利用
	    if ($opt{ipsj} && $opt{use_block_type}) {
		foreach my $tag (@ISTVAN_TAGS) {
		    if ($_ =~ /$tag=\"([^\"]+?)\"/) {
			my $values = $1;
			foreach my $value (split ("/", $values)) {
			    my ($begin, $end) = ($value =~ /B:(\d+),E:(\d+)/);
			    push (@{$results_of_istvan{$sid}{$tag}}, {begin => $begin, end => $end});
			}
		    }
		}
	    }


	    $sid2blockType{$sid} = $blockType;
 	}
	elsif ($_ =~ $pattern_end) {
	    $content .= $1;

	    my $terms = &extractIndices($content, $indexer, $file, $indexer_genkei, \%pos2synnode, \%pos2info);

	    # インリンクの場合は披リンク数分を考慮する
	    if ($tagName eq 'InLink') {
		my $num_of_linked_pages = 0;
		for my $line (split(/\n/, $content)) {
		    if ($line =~ /<\/DocID>$/) {
			$num_of_linked_pages++;
		    }
		}

		foreach my $term (@$terms) {
		    $term->{score} *= $num_of_linked_pages;
		    $term->{freq} *= $num_of_linked_pages;
		}

		# inlinkから抽出した場合は領域タグACを追加
		$sid2blockType{$sid} = $prefixOfBlockType{inlink};
	    }
	    $indices{$sid} = $terms if (defined $terms);

	    $isIndexingTarget = 0;
	    $tagName = '';
	    $content = '';
	}
	else {
	    if ($isIndexingTarget) {
		$content .= $_;
	    }
	}
    }
    close(READER);

    # 索引のマージ
    return &merge_indices(\%indices, \%sid2blockType, \%results_of_istvan, \%pos2synnode, \%pos2info, $file);
}



sub extractIndices {
    my ($content, $indexer, $file, $indexer_genkei, $pos2synnode, $pos2info) = @_;

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

	# 同位語の情報を付与
	$annotation = $ECTS->annotateDBInfo($annotation, {knp_result => 1}) if ($opt{penalty});

	my $terms_syn = $indexer->makeIndexfromSynGraph($annotation,
							\@contentWordFeatures,
							$pos2synnode,
							$pos2info,
							{ use_of_syngraph_dependency => !$opt{ignore_syn_dpnd},
							  use_of_hypernym => !$opt{ignore_hypernym},
							  use_of_negation_and_antonym => 1,
							  verbose => $opt{verbose}} );
	my ($rawstring) = ($content =~ m!<RawString>(.+?)</RawString>!);

	unless (defined $terms_syn) {
	    print STDERR "[SKIP] A large number of indices are extracted from [$rawstring]: $file (limit=" . $opt{max_num_of_indices} . ")\n";
	}

	# 出現形インデックスを抽出しマージする
	if (!$opt{ignore_genkei}) {
	    my $knp_result_obj = new KNP::Result($knp_result);
	    my $terms_genkei = $indexer_genkei->makeIndexFromKNPResultObject($knp_result_obj);
	    push(@$terms, @$terms_genkei) if (defined $terms_genkei);
	    push(@$terms, @$terms_syn) if (defined $terms_syn);
	} else {
	    $terms = $terms_syn;
	}
    }
    elsif ($opt{english}) {
	if ($opt{scheme} eq 'CoNLL') {
	    $terms = $indexer->makeIndexFromCoNLLFormat($annotation, \%opt);
	} else {
	    $terms = $indexer->makeIndexFromEnglishData($annotation, \%opt);
	}
    }
    elsif ($opt{knp}) {
	my $terms_knp = $indexer->makeIndexFromKNPResult($knp_result, \%opt);

	# 出現形インデックスを抽出しマージする
	if (!$opt{ignore_genkei}) {
	    my $knp_result_obj = new KNP::Result($knp_result);
	    my $terms_genkei = $indexer_genkei->makeIndexFromKNPResultObject($knp_result_obj);
	    push(@$terms, @$terms_genkei) if (defined $terms_genkei);
	    push(@$terms, @$terms_knp) if (defined $terms_knp);
	} else {
	    $terms = $terms_knp;
	}
    }
    else {
	$terms = $indexer->makeIndexfromJumanResult($annotation);
    }

    if ($opt{verbose}) {
	foreach my $e (@$terms) {
	    while (my ($k, $v) = each %$e) {
		print STDERR $k . " " . $v . "\n";
	    }
	}
    }

    return $terms;
}

sub extract_indice_from_single_file {
    my ($file, $fid) = @_;

    return if (exists $alreadyAnalyzedFiles{$file});

    syswrite LOG, "$file " if $opt{logfile};

    # ファイルサイズのチェック
    if ($opt{skip_large_file}) {
	my $st = stat($file);
	unless ($st) {
	    syswrite LOG, "error\n" if ($opt{logfile});
	    return;
	}

	if ($st->size > $opt{skip_large_file}) {
	    print STDERR "Too large file: $file (" . $st->size . " bytes > limit=$opt{skip_large_file} bytes)\n";
	    syswrite LOG, "large_file\n" if ($opt{logfile});
	    return;
	}
    }

    try {
	# タイムアウトの設定
	local $SIG{ALRM} = sub {die sprintf (qq([WARNING] Time out occured! (time=%d [sec], file=%s)), $opt{timeout}, $file)};
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
	    if ($opt{only_inlinks}) {
		open(WRITER, "| gzip > $opt{out}/$fid.link.idx.gz");
	    } else {
		open(WRITER, "| gzip > $opt{out}/$fid.idx.gz");
	    }
	    binmode(WRITER, ':utf8');
	} else {
	    if ($opt{only_inlinks}) {
		open(WRITER, "| gzip > $opt{out}/$fid.link.idx");
	    } else {
		open(WRITER, '>:utf8', "$opt{out}/$fid.idx");
	    }
	}

	# NTCIRで提供されている文書の場合は、$fidから先頭のNWを削除
	$fid =~ s/^NW//;

	if ($opt{position}) {
	    if ($opt{knp} || $opt{syn} || $opt{english}) {
		&output_syngraph_indice_with_position(*WRITER, $fid, $indice);
	    } else {
		&output_with_position(*WRITER, $fid, $indice);
	    }
	} else {
	    if ($opt{knp} || $opt{syn} || $opt{english}) {
		&output_syngraph_indice_wo_position(*WRITER, $fid, $indice);
	    } else {
		&output_wo_position(*WRITER, $fid, $indice);
	    }
	}
	close(WRITER);
	print STDERR " done.\n" if ($opt{verbose});
	syswrite LOG, "success\n" if ($opt{logfile});
	if ($opt{offset}) {
	    my ($sid) = ($file =~ /(\d+(\-\d+)?)[^\/]+$/);
	    syswrite SID2TID, "$sid $fid\n";
	}
    } catch Error with {
	my $err = shift;
	print STDERR "Exception ocurred in $file\n";
	print STDERR "Exception at line ", $err->{-line} ," in ", $err->{-file}, " (", $err->{-text}, ")\n";
	syswrite LOG, "timeout\n" if ($opt{logfile});
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
			       without_using_repname => $opt{genkei},
			       MAX_NUM_OF_TERMS_FROM_SENTENCE => $opt{max_num_of_indices}
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
    my ($indices, $sid2blockType, $results_of_istvan, $pos2synnode, $pos2info, $file) = @_;

    # 係り受けタームだけ抜き出す
    my %midasiOfDpndancyTerm = ();
    if ($opt{penalty}) {
	foreach my $sid (sort {$a <=> $b} keys %$indices) {
	    foreach my $term (@{$indices->{$sid}}) {
		$midasiOfDpndancyTerm{$term->{midasi}} = 1 if ($term->{midasi} =~ /\->/);
	    }
	}
    }

    # 索引のマージ
    my %ret;
    my %coords = ();
    foreach my $sid (sort {$a <=> $b} keys %$indices) {
	my $blockType = $prefixOfBlockType{$sid2blockType->{$sid}};
	foreach my $index (@{$indices->{$sid}}) {

	    ##########################
	    # ブロックタイプタグを取得
	    ##########################

	    # 領域判定結果に対応したタグ
	    my @tags = ();
	    if ($opt{use_block_type}) {
		push (@tags, sprintf ("%s:", $blockType));
		# 論文検索の場合は istvan さんの結果も利用する
		if ($opt{ipsj}) {
		    foreach my $type_of_istvan (keys %{$results_of_istvan->{$sid}}) {
			my $annotation_data = $results_of_istvan->{$sid}{$type_of_istvan};
			foreach my $data (@$annotation_data) {
			    if ($data->{begin} <= $index->{_pos} && $index->{_pos} <= $data->{end}) {
				push (@tags, sprintf ("%s:", $prefixOfStringType{$type_of_istvan}));
			    }
			}
		    }
		}
	    } else {
		push (@tags, "");
	    }


	    ##########################
	    # タームの集約
	    ##########################

	    foreach my $tag (@tags) {
		my $midasi = ($opt{feature}) ? $index->{midasi} : sprintf ("%s%s", $tag, $index->{midasi});
		next if ($midasi =~ /\->/ && $midasi =~ /s\d+/ && $opt{ignore_syn_dpnd});
		chop $tag if ($opt{feature});

		if ($opt{penalty}) {
		    # ペナルティタームの生成
		    if (exists $midasiOfDpndancyTerm{$index->{midasi}}) {
			my $_dpnds1 = &makePenaltyTerms ($index, $pos2synnode, $pos2info, 1, $file, \%midasiOfDpndancyTerm);
			my $_dpnds2 = &makePenaltyTerms ($index, $pos2synnode, $pos2info, 0, $file, \%midasiOfDpndancyTerm);

			foreach my $_dpnds (($_dpnds1, $_dpnds2)) {
			    foreach my $_dpnd (@$_dpnds) {
				next unless (defined $_dpnd);

				my $__dpnd = $_dpnd;
				if ($opt{feature}) {
				    push (@{$ret{$__dpnd}->{pos_score}}, {pos => $index->{pos}, score => -1 * $index->{score}, feature => $BLOCK_TYPE2FEATURE{$tag} });
				} else {
				    $__dpnd = sprintf ("%s%s\$", $tag, $_dpnd);
				    push (@{$ret{$__dpnd}->{pos_score}}, {pos => $index->{pos}, score => -1 * $index->{score}});
				}
				$ret{$__dpnd}->{score} -= $index->{score};
				$ret{$__dpnd}->{sids}{$sid} = 1;
			    }
			}
		    }
		}



		$ret{$midasi}->{sids}{$sid} = 1;
		if ($opt{knp} || $opt{syn} || $opt{english}) {
		    if ($opt{feature}) {
			push (@{$ret{$midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score}, feature => $BLOCK_TYPE2FEATURE{$tag} });
		    } else {
			push (@{$ret{$midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score} });
		    }
		    $ret{$midasi}->{score} += $index->{score};
		} else {
		    push(@{$ret{$midasi}->{poss}}, @{$index->{absolute_pos}});
		    $ret{$midasi}->{freq} += $index->{freq};
		}
	    }
	}
    }

    return \%ret;
}

# 同義語の獲得
sub getSynonyms {
    my ($synids) = @_;

    my @synonyms = ();
    foreach my $synid (@$synids) {
	next unless (defined $synid);
	foreach my $string (@{$SYNDB{$synid}}) {
	    push (@synonyms, $string);
	}
    }
    return \@synonyms;
}

# 同位語をもとにペナルティタームを作成する
sub makePenaltyTerms {
    my ($term, $pos2synnode, $pos2info, $forMoto, $file, $midasiOfDpndancyTerm) = @_;

    my $pos = $term->{pos};
    my ($moto, $saki) = ($term->{midasi} =~ /^(.+?)\->(.+?)$/);
    my $_moto = $moto; $_moto =~ s/\*$//;
    my $_saki = $saki; $_saki =~ s/\*$//;

    # 原形かどうかのチェック
    my $isGenkei = ($moto =~ /\*$/ || $saki =~ /\*$/) ? 1 : 0;

    my $tid;
    my $synonyms;
    if ($forMoto) {
	# 係り元が属す表現のIDを獲得（機->計算機）
	$tid = $pos2info->{$term->{moto_pos}}->{tid} if (exists $pos2info->{$term->{moto_pos}});
	# pos2infoから同位語の情報が得られない場合は、係り先の語に関して同位語DBを引く
	$tid = $ECTS->term2id($_moto) unless (defined $tid);

	# 係り先の語の同義語を取得
	$synonyms = &getSynonyms($pos2synnode->{$term->{saki_pos}});
    } else {
	# 係り先が属す表現のIDを獲得（機->計算機）
	$tid = $pos2info->{$term->{saki_pos}}->{tid} if (exists $pos2info->{$term->{saki_pos}});
	# 係り先が属す表現の一部に係り元がなっていないかチェック（計算が計算->機の一部でないかどうか）
	$tid = undef if (exists $pos2info->{$term->{saki_pos}} && $term->{saki_pos} - $term->{moto_pos} < $pos2info->{$term->{saki_pos}}->{length});
	# pos2infoから同位語の情報が得られない場合は、係り先の語に関して同位語DBを引く
	$tid = $ECTS->term2id($_saki) unless (defined $tid);

	# 係り元の語の同義語を取得
	$synonyms = &getSynonyms($pos2synnode->{$term->{moto_pos}});
    }

    my @penaltyTerms = ();
    if (defined $tid) {
	my $bgn = $pos - $DIST_FOR_MAKING_COORD_DPND; $bgn = 0 if ($bgn < 0);
	my $end = $pos + $DIST_FOR_MAKING_COORD_DPND;
	foreach my $_pos ($bgn..$end) {
	    next unless (exists $pos2info->{$_pos});
	    my $info = $pos2info->{$_pos};
	    next if ($info->{tid} == $tid);

	    # 同位語を獲得
	    my $near_coords = &get_near_coords($tid, $info);
	    # 同位語からペナルティタームを生成
	    foreach my $coord (@$near_coords) {
		next unless ($_moto ne $coord && $_saki ne $coord);

		my $_coord = ($isGenkei) ? sprintf ("%s*", $coord) : $coord;

		# ペナルティタームの生成
		my $_term = ($forMoto) ? sprintf ("%s->%s", $_coord, $saki) : sprintf ("%s->%s", $moto, $_coord);

		# ペナルティタームと同じ係り受けタームが文書中に存在するかどうかチェック
		if (exists $midasiOfDpndancyTerm->{$_term}) {
		    $_term = undef;
		} else {
		    # 同義語をチェック
		    # オーロラ->発生 が既にある場合は オーロラ->生じる は除く
		    foreach my $synonym (@$synonyms) {
			my $_synonym = ($isGenkei) ? sprintf ("%s*", $synonym) : $synonym;
			my $__term = ($forMoto) ? sprintf ("%s->%s", $_coord, $_synonym) : sprintf ("%s->%s", $_synonym, $_coord);
			if (exists $midasiOfDpndancyTerm->{$__term}) {
			    $_term = undef; last;
			}
		    }

		    # 下位語をチェック
		    # 酵母->カレー/パン から 酵母->パン が作られている場合は除く
		    foreach my $hyponym (@{$HYPODB{$_coord}}) {
			my $_hyponym = ($isGenkei) ? sprintf ("%s*", $hyponym) : $hyponym;
			my $__term = ($forMoto) ? sprintf ("%s->%s", $_hyponym, $saki) : sprintf ("%s->%s", $moto, $_hyponym);
			if (exists $midasiOfDpndancyTerm->{$__term}) {
			    $_term = undef; last;
			}
		    }
		}
		push (@penaltyTerms, $_term) if ($_term);
	    }
	}
    }

    return \@penaltyTerms;
}

# 同位語を獲得
sub get_near_coords {
    my ($tid, $info) = @_;

    my @coords = ();
    foreach my $i (0..(scalar(@{$info->{offset}}) - 1)) {
	my $tids = $ECTS->read($info->{offset}[$i], $info->{byteLength}[$i]);
	push (@coords, $info->{midasi}) if (exists $tids->{$tid});
    }

    return \@coords;
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
	my $pos_scr_msk_str;
	foreach my $pos_score (sort {$a->{pos} <=> $b->{pos}} @{$indice->{$midasi}{pos_score}}) {
	    my $pos = $pos_score->{pos};
	    my $msk = $pos_score->{feature} + 0;
	    my $scr = &round($pos_score->{score});
	    if ($opt{feature}) {
		$pos_scr_msk_str .= $pos . "&" . $scr . "&" . $msk . ",";
	    } else {
		$pos_scr_msk_str .= $pos . "&" . $scr . ",";
	    }
	}
	chop($pos_scr_msk_str);

	printf $fh ("%s %s:%s@%s#%s\n", $midasi, $did, $score, $sids_str, $pos_scr_msk_str);
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
