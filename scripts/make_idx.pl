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

binmode(STDIN,  ":utf8");
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
	   'rawresult',
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
    untie %_SYNDB;

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

# 格・係り受けタイプの素性ビット

my %CASE_FEATURE_BIT = ();
$CASE_FEATURE_BIT{ガ}     = (2 ** 9);
$CASE_FEATURE_BIT{ヲ}     = (2 ** 10);
$CASE_FEATURE_BIT{ニ}     = (2 ** 11);
$CASE_FEATURE_BIT{ヘ}     = (2 ** 12);
$CASE_FEATURE_BIT{ト}     = (2 ** 13);
$CASE_FEATURE_BIT{デ}     = (2 ** 14);
$CASE_FEATURE_BIT{カラ}   = (2 ** 15);
$CASE_FEATURE_BIT{マデ}   = (2 ** 16);
$CASE_FEATURE_BIT{ヨリ}   = (2 ** 17);
$CASE_FEATURE_BIT{修飾}   = (2 ** 18);
$CASE_FEATURE_BIT{時間}   = (2 ** 19);
$CASE_FEATURE_BIT{ノ}     = (2 ** 20);
$CASE_FEATURE_BIT{ニツク} = (2 ** 21);
$CASE_FEATURE_BIT{トスル} = (2 ** 22);
$CASE_FEATURE_BIT{その他} = (2 ** 23);

my %DPND_TYPE_FEATURE_BIT = ();
$DPND_TYPE_FEATURE_BIT{未格}   = (2 ** 24);
$DPND_TYPE_FEATURE_BIT{連体}   = (2 ** 25);
$DPND_TYPE_FEATURE_BIT{省略}   = (2 ** 26);
$DPND_TYPE_FEATURE_BIT{受動}   = (2 ** 27);
$DPND_TYPE_FEATURE_BIT{使役}   = (2 ** 28);
$DPND_TYPE_FEATURE_BIT{可能}   = (2 ** 29);
$DPND_TYPE_FEATURE_BIT{自動}   = (2 ** 30);
$DPND_TYPE_FEATURE_BIT{授動詞} = (2 ** 31);
# $DPND_TYPE_FEATURE_BIT{否定}   = (2 ** 32);


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








################################
# メイン処理
################################

&main();

################################
# 後処理
################################

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

    $show_usage = 0 if (($opt{file} || $opt{in} || $opt{rawresult}) && $opt{out});
    $show_usage = 0 if ($opt{infiles} && $opt{outdir_prefix});
    &usage() if ($show_usage);

    die "Not found! $opt{in}\n" unless (-e $opt{in} || -e $opt{file} || -e $opt{infiles} || $opt{rawresult});

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
    elsif ($opt{rawresult}) {
	my @data = ();
	my $prevSID = undef;
	my $numOfSent = 0;
	while (<STDIN>) {
	    if ($_ =~ /^\# S\-ID:w\d+\-(.+) BlockType/) {
		my $SID_SentID = $1;
		my @field = split ("-", $SID_SentID);
		my $sentID = pop @field;
		my $SID = join ("-", @field);

		if (defined $prevSID && $SID eq $prevSID) {
		    $numOfSent++;
		} else {
		    &extract_indice_from_single_file("stdin", $prevSID, \@data);

		    @data = ();
		    $numOfSent = 0;
		    $ECTS->clear() if ($opt{penalty});
		}
		$prevSID = $SID;
	    }
	    push (@{$data[$numOfSent]}, $_);
	}
	$prevSID = 0 unless (defined $prevSID);
	&extract_indice_from_single_file("stdin", $prevSID, \@data);
    }
}

######################################
# 標準フォーマットからタームを抽出する
######################################

sub extract_indices_wo_pm {
    my ($file, $fid, $data, $my_opt) = @_;

    ##################
    # インデクサの準備
    ##################

    # 代表表記、同義語・句
    my $indexerRepname = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	MAX_NUM_OF_TERMS_FROM_SENTENCE => $opt{max_num_of_indices},
	without_using_repname => $opt{genkei} });

    # 出現形のみ
    my $indexerGenkei = new Indexer({
	ignore_yomi => $opt{ignore_yomi},
	MAX_NUM_OF_TERMS_FROM_SENTENCE => $opt{max_num_of_indices},
	genkei => 1 });


    ##################################
    # インデックス対象とする領域を設定
    ##################################

    my @targetTags;
    push(@targetTags, 'Title')       if ($opt{title});
    push(@targetTags, 'Keywords')    if ($opt{keywords});
    push(@targetTags, 'Description') if ($opt{description});
    push(@targetTags, 'InLink')      if ($opt{inlinks});
    push(@targetTags, 'S')           if ($opt{sentences});
    push(@targetTags, 'Keywords')    if ($opt{keyword});
    push(@targetTags, 'Keyword')     if ($opt{keyword});
    push(@targetTags, 'Authors')     if ($opt{author});
    push(@targetTags, 'Author')      if ($opt{author});
    push(@targetTags, 'Abstract')    if ($opt{abstract});


    # インデキシングに利用する変数
    my (%terms, %sid2blockType, %results_of_istvan, %pos2synnode, %pos2info, %eid2string) = ((), (), (), (), (), ());

    if ($opt{rawresult}) {
	# 生の解析結果からタームを抽出
	&extractTermsFromRawResult($file, $data, $fid, $indexerRepname, $indexerGenkei, \@targetTags, \%terms, \%sid2blockType, \%results_of_istvan, \%pos2synnode, \%pos2info, \%eid2string, $my_opt);
    } else {
	# 標準フォーマットからタームを抽出
	&extractTermsFromStandardFormat($file, $fid, $indexerRepname, $indexerGenkei, \@targetTags, \%terms, \%sid2blockType, \%results_of_istvan, \%pos2synnode, \%pos2info, $my_opt);
    }

    # 個々の文から抽出されたタームのマージ
    return &merge_indices(\%terms, \%sid2blockType, \%results_of_istvan, \%pos2synnode, \%pos2info, $file, \%eid2string);
}

sub extractTermsFromRawResult {
    my ($file, $data, $fid, $indexerRepname, $indexerGenkei, $targetTags, $TERMS, $sid2blockType, $results_of_istvan, $pos2synnode, $pos2info, $eid2string) = @_;

    foreach my $linguisticAnalysisResult (@$data) {
	my $sid;
	my $comment = shift @$linguisticAnalysisResult;
	my $lingResult = join ("", @$linguisticAnalysisResult);
	if ($comment =~ /^\# S\-ID:w\d+\-(.+) BlockType:(.+?) JUMAN/) {
	    my $SID_SentID = $1;
	    my $blockType  = $2;
	    my @field = split ("-", $SID_SentID);
	    $sid = pop @field;
	    my $fid = join ("-", @field);
	    $sid2blockType->{$sid} = $blockType;
	}

	# タームの抽出
	my $terms = &extractIndices($lingResult, $indexerRepname, $file, $indexerGenkei, $pos2synnode, $pos2info, "", $eid2string);
	$TERMS->{$sid} = $terms if (defined $terms);
    }
}

sub extractTermsFromStandardFormat {
    my ($file, $fid, $indexerRepname, $indexerGenkei, $targetTags, $TERMS, $sid2blockType, $results_of_istvan, $pos2synnode, $pos2info, $my_opt) = @_;

    my $sid;
    # Title, Keywords, Description, Inlink には文IDがないため、-100000からカウントする
    my $meta_sid = -100000;
    my $isIndexingTarget = 0;
    my $tagName;
    my $blockType;
    my $rawstring;
    my $content;

    # パターンを生成
    my $pattern = join("|", @$targetTags);
    my $pattern_start = qr/^\s*(<($pattern)(?: |\>).*\n)/o;
    my $pattern_end   = qr/^(.*\<\/($pattern)\>)/o;


    ########################
    # ファイルハンドラを開く
    ########################
    if ($my_opt->{gzipped}) {
	open(READER, "zcat $file 2> /dev/null |");
    } else {
	open(READER, $file);
    }
    binmode(READER, ':utf8');

    LOOP:
    while (<READER>) {
	last if ($_ =~ /<Text / && $opt{only_inlinks});

	if ($_ =~ /<RawString>([^<]+?)<\/RawString>/) {
	    $rawstring = $1;
	}

	# インデキシング対象領域であればバッファに言語解析結果を保存
	if ($_ !~ /^(?:\s|\])/) {
	    if ($isIndexingTarget) {
		$content .= $_;
	    }
	}
	# 開始タグ
	elsif ($_ =~ $pattern_start) {
	    ($isIndexingTarget, $content, $tagName) = (1, $1, $2);

	    # 文字数が多い文はスキップ
	    if ($_ =~ /Length=\"(\d+)\"/) {
		my $length = $1;
		# $opt{max_length_of_rawstring}バイトより大きい場合は読み込まない, 越える場合は文字化け、英数字の羅列の可能性
		if ($length > $opt{max_length_of_rawstring}) {
		    my $_rawstring = <READER>;
		    while (<READER>) {
			if (/(.*\<\/($pattern)\>)/o) {
			    ($isIndexingTarget, $content, $tagName) = (0, '', '');
			    next LOOP;
			}
		    }
		}
	    }

	    ############################
	    # ブロックタイプと文IDの取得
	    ############################

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
		$sid = $1;
	    }
	    elsif (/\<(?:$pattern)/) {
		$meta_sid += 2;
		$sid = $meta_sid;
	    }
	    print STDERR "\rdir=$opt{in},file=$fid (Id=$sid)" if ($opt{verbose});

	    # istvan's result を利用
	    if ($opt{ipsj} && $opt{use_block_type}) {
		foreach my $tag (@ISTVAN_TAGS) {
		    if ($_ =~ /$tag=\"([^\"]+?)\"/) {
			my $values = $1;
			foreach my $value (split ("/", $values)) {
			    my ($begin, $end) = ($value =~ /B:(\d+),E:(\d+)/);
			    push (@{$results_of_istvan->{$sid}{$tag}}, {begin => $begin, end => $end});
			}
		    }
		}
	    }
	    $sid2blockType->{$sid} = $blockType;
 	}
	# 終了タグ
	elsif ($_ =~ $pattern_end) {
	    $content .= $1;

	    # 言語解析部分の取得
	    my ($linguisticAnalysisResult) = ($content =~ /<Annotation[^>]+?>\<\!\[CDATA\[((.|\n)+)\]\]\><\/Annotation>/);

	    # タームの抽出
	    my $terms = &extractIndices($linguisticAnalysisResult, $indexerRepname, $file, $indexerGenkei, $pos2synnode, $pos2info, $rawstring);

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
		$sid2blockType->{$sid} = $prefixOfBlockType{inlink};
	    }
	    $TERMS->{$sid} = $terms if (defined $terms);

	    ($isIndexingTarget, $content, $tagName) = (0, '', '');
	}
	else {
	    if ($isIndexingTarget) {
		$content .= $_;
	    }
	}
    }
    close(READER);
}


##################
# タームを抽出する
##################

sub extractIndices {
    my ($linguisticAnalysisResult, $indexer, $file, $indexer_genkei, $pos2synnode, $pos2info, $rawstring, $eid2string) = @_;

    return if ($linguisticAnalysisResult eq '');

    my $knp_result;
    if ($opt{scheme} eq 'SynGraph') {
	# `空行 or !' or '#' ではじまる行はスキップ
	$knp_result = join ("\n", grep { $_ ne '' && $_ !~ /^(?:!|\#)/ } split ("\n", $linguisticAnalysisResult));
    } else {
	$knp_result = $linguisticAnalysisResult;
    }

    my $terms;
    if ($opt{syn}) {
	# 基本句内の内容語の素性を取得
	my ($eid, @buf, @contentWordFeatures) = ((), (), ());
	foreach my $line (split (/\n/, $knp_result)) {
	    next if ($line =~ /^\* /);
	    if ($line =~ /^[\+ |EOS]/) {
		if (scalar(@buf)) {
		    my $contentWord = $buf[-1];
		    foreach my $mrph (@buf) {
			if ($mrph =~ /<内容語>/) {
			    $contentWord = $mrph;
			    last;
			}
		    }

		    if ($contentWord =~ m!<代表表記:([^/]+)!) {
			$eid2string->{$eid}{$1} = 1;
		    }

		    if ($contentWord =~ /((?:<[^>]+>)+)$/) {
			push (@contentWordFeatures, $1);
		    } else {
			print "\? $contentWord\n";
			exit;
		    }
		    @buf = ();
		}
		$eid = $1 if ($line =~ /<EID:(\d+)>/);
	    } else {
		push (@buf, $line);
	    }
	}

	# 同位語の情報を付与(ペナルティターム生成時)
	$linguisticAnalysisResult = $ECTS->annotateDBInfo($linguisticAnalysisResult, {knp_result => 1}) if ($opt{penalty});

	# ターム（代表表記，同義語・句，係り受け）
	my $terms_syn = $indexer->makeIndexfromSynGraph($linguisticAnalysisResult,
							\@contentWordFeatures,
							$pos2synnode,
							$pos2info,
							{ use_of_syngraph_dependency => !$opt{ignore_syn_dpnd},
							  use_of_hypernym => !$opt{ignore_hypernym},
							  use_of_negation_and_antonym => 1,
							  verbose => $opt{verbose}} );
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
	    $terms = $indexer->makeIndexFromCoNLLFormat($linguisticAnalysisResult, \%opt);
	} else {
	    $terms = $indexer->makeIndexFromEnglishData($linguisticAnalysisResult, \%opt);
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
	$terms = $indexer->makeIndexfromJumanResult($linguisticAnalysisResult);
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
    my ($file, $fid, $data) = @_;

    return if (exists $alreadyAnalyzedFiles{$file});

    syswrite LOG, "$file " if $opt{logfile};

    # ファイルサイズのチェック（rawresultの場合はチェックしない）
    if ($opt{skip_large_file} && !$opt{rawresult}) {
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
	    $indice = &extract_indices_wo_pm($file, $fid, $data, {gzipped => $opt{z}});
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
    my ($indices, $sid2blockType, $results_of_istvan, $pos2synnode, $pos2info, $file, $eid2string) = @_;

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

		# ブロックタイプ素性
		my $feature = $BLOCK_TYPE2FEATURE{$tag};

		# 係り受け素性
		if ($opt{feature}) {
		    unless ($midasi =~ /^(.+)\->(.+)$/) {
			unless ($index->{midasi} =~ /s\d+/) {
			    my ($CASE_F_ID, $CASE_ELMT);
			    if ($index->{kihonku_fstring} =~ /<格構造:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
				$CASE_F_ID = $1;
				$CASE_ELMT = $2;
				foreach my $caseElement (split (";", $CASE_ELMT)) {
				    my ($_case, $type, $label, $eid) = split ("/", $caseElement);
				    if ($type eq 'O') {
					foreach my $_label (keys %{$eid2string->{$eid}}) {
					    my $_midasi = sprintf ("%s->%s", $_label, $index->{midasi});
					    my $_feature = $feature;
					    $_feature += $CASE_FEATURE_BIT{$_case};
					    $_feature += $DPND_TYPE_FEATURE_BIT{省略};
					    $ret{$_midasi}->{sids}{$sid} = 1;
					    push (@{$ret{$_midasi}->{pos_score}}, {pos => $index->{pos}, score => 1, feature => $_feature});
					}
				    }
				}
			    }
			}
		    } else {
			my ($kakarimoto, $kakarisaki) = ($1, $2);

			if ($index->{kakarimoto_fstring} =~ /<換言:(\+N[^>]+)>/) {
			    foreach my $pattern (split (";", $1)) {
				my ($case, $predicate) = ($pattern =~ /\+N:N(.)(.+)/);
				$case =~ tr/あ-ん/ア-ン/;
				my $_midasi = sprintf ("%s->%s", $kakarisaki, $predicate);
				my $_feature = $feature;
				$_feature += $CASE_FEATURE_BIT{$case};
				$_feature += $DPND_TYPE_FEATURE_BIT{連体};
				$ret{$_midasi}->{sids}{$sid} = 1;
				push (@{$ret{$_midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score}, feature => $_feature});
			    }
			}

			if ($index->{kakarisaki_fstring} =~ /<換言:(N\+[^>]+)>/) {
			    foreach my $pattern (split (";", $1)) {
				my ($case, $predicate) = ($pattern =~ /N\+:N(.)(.+)/);
				$case =~ tr/あ-ん/ア-ン/;
				my $_midasi = sprintf ("%s->%s", $kakarimoto, $predicate);
				my $_feature = $feature;
				$_feature += $CASE_FEATURE_BIT{$case};
				$ret{$_midasi}->{sids}{$sid} = 1;
				push (@{$ret{$_midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score}, feature => $_feature});
			    }
			}

			my ($_midasi, $_feature) = &appendDpndFeature($midasi, $kakarimoto, $kakarisaki, $index);
			$midasi = $_midasi;
			$feature += $_feature;
		    }
		}


		$ret{$midasi}->{sids}{$sid} = 1;
		if ($opt{knp} || $opt{syn} || $opt{english}) {
		    if ($opt{feature}) {
			push (@{$ret{$midasi}->{pos_score}}, {pos => $index->{pos}, score => $index->{score}, feature => $feature});
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




# 係り受け素性を追加
sub appendDpndFeature {
    my ($midasi, $kakarimoto, $kakarisaki, $index) = @_;

    my $isSurfForm = 0;
    if ($kakarimoto =~ /\*$/) {
	chop $kakarimoto;
	chop $kakarisaki;
	$isSurfForm = 1;
    }

    my $flag_saki = 1;
    my $featureBit = 0;
    my $case = 'その他';
    my @dpndTypes = ();

    my $isRentai = ($index->{kakarimoto_kihonku_fstring} =~ /<係:連格>/) ? 1: 0;
    my $mrphF    = $index->{kakarisaki_fstring};

    my $kihonkuF = $index->{kakarisaki_kihonku_fstring};
    my $kakarimotoSurf = $index->{kakarimoto_surf};
    my $suffix   = '';
    if ($isRentai) {
	$mrphF    = $index->{kakarimoto_fstring};
	$kihonkuF = $index->{kakarimoto_kihonku_fstring};
	$kakarimotoSurf = $index->{kakarisaki_surf};
	push (@dpndTypes, '連体');
	# 連体修飾の場合は係り元と係り先を入れ替える
	my $_tmp = $kakarimoto;
	$kakarimoto = $kakarisaki;
	$kakarisaki = $_tmp;
	if ($isSurfForm) {
	    $midasi = sprintf ("%s*->%s*", $kakarimoto, $kakarisaki);
	} else {
	    $midasi = sprintf ("%s->%s", $kakarimoto, $kakarisaki);
	}
    } else {
#	$case = 'ノ' if ($index->{kakarimoto_kihonku_fstring} =~ /<係:(?:ノ格|文節内)>/);
#	$case = 'ノ' if ($index->{kakarimoto_kihonku_fstring} =~ /<係:ノ格>/);
    }

    my ($CASE_F_ID, $CASE_ELMT);
    if ($kihonkuF =~ /<格構造:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
	$CASE_F_ID = $1;
	$CASE_ELMT = $2;
    }
    my ($N_CASE_F_ID, $N_CASE_ELMT);
    if ($kihonkuF =~ /<正規化格解析結果-0:([^:]+:[^:]+(?::[PC]+)?\d+):([^>]+)>/) {
	$N_CASE_F_ID = $1;
	$N_CASE_ELMT = $2;
    }

    if ($CASE_F_ID =~ /CP/) {
	push (@dpndTypes, '使役');
	push (@dpndTypes, '受動');
	$suffix = '<使役><受動>';
    }
    elsif ($CASE_F_ID =~ /C/) {
	push (@dpndTypes, '使役');
	$suffix = '<使役>';
    }
    elsif ($CASE_F_ID =~ /P/) {
	push (@dpndTypes, '受動');
	$suffix = '<受動>';
    }

    # 正規化格解析
    foreach my $caseElement (split (";", $N_CASE_ELMT)) {
	my ($_case, $type, $label, $eid) = split ("/", $caseElement);

	# チェック
	next unless ($label =~ /[$kakarimoto|$kakarimotoSurf]$/);

	if ($N_CASE_F_ID =~ m!^([^/]+)!) {
	    $kakarisaki = $1;
	    if ($isSurfForm) {
		$midasi = sprintf ("%s*->%s*", $kakarimoto, $kakarisaki);
	    } else {
		$midasi = sprintf ("%s->%s", $kakarimoto, $kakarisaki);
	    }
	}

	if ($type eq 'N' && !$isRentai) {
	    push (@dpndTypes, '未格');
	}
	elsif ($type eq 'O') {
	    push (@dpndTypes, '省略');
	}
	$case = $_case;
	last;
    }

    if ($case eq 'その他') {
	# 格構造
	foreach my $caseElement (split (";", $CASE_ELMT)) {
	    my ($_case, $type, $label, $eid) = split ("/", $caseElement);

	    # チェック
	    next unless ($label =~ /[$kakarimoto|$kakarimotoSurf]$/);

	    if (!$isRentai && $index->{kakarimoto_kihonku_fstring} =~ /<係:未格>/) {
		push (@dpndTypes, '未格');
	    }
	    elsif ($type eq 'O') {
		push (@dpndTypes, '省略');
	    }

	    # <使役><受動>をタームに付与
	    $midasi .= $suffix;
	    $case = $_case;
	    last;
	}
    }

    push (@dpndTypes, '自動')   if ($mrphF =~ /<自他動詞:他/);
    push (@dpndTypes, '授動詞') if ($mrphF =~ /<授受動詞:受/);

    my $featureBit = $CASE_FEATURE_BIT{$case};
    my @featureBuf = ($case);
    foreach my $dpndType (@dpndTypes) {
	$featureBit |= $DPND_TYPE_FEATURE_BIT{$dpndType};
	push (@featureBuf, $dpndType);
    }
#    print $midasi . " " . join (",", @featureBuf) . "\n";

    return ($midasi, $featureBit);
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




########################################
# 出力
########################################

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
#	    my $msk = sprintf ("%032b", $pos_score->{feature} + 0);
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
