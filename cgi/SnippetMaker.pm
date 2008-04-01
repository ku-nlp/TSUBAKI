package SnippetMaker;

use strict;
use Encode qw(encode decode from_to);
use utf8;

use KNP;
use Indexer;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;



my $SF_DIR_PREFFIX1 = "/data/xmls";
my $SF_DIR_PREFFIX1 = "/data/sfs";
my $SF_DIR_PREFFIX2 = "/data/sfs_w_syn";
my $SF_DIR_PREFFIX3 = "/net2/nlpcf34/disk09/skeiji/sfs_w_syn";
my $SF_DIR_PREFFIX4 = "/net2/nlpcf34/disk03/skeiji/sfs_w_syn";
my $SF_DIR_PREFFIX5 = "/net2/nlpcf34/disk08/skeiji";

sub extract_sentences_from_ID {
    my($query, $id, $opt) = @_;

    my $xmlfile;
    if ($opt->{syngraph}) {
	$xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX2, $id / 1000000, $id / 10000, $id);
	$xmlfile = sprintf("%s/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX3, $id / 10000, $id) unless (-e $xmlfile);
	$xmlfile = sprintf("%s/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX4, $id / 10000, $id) unless (-e $xmlfile);
	$xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX1, $id / 1000000, $id / 10000, $id) unless (-e $xmlfile);
    } else {
	$xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX1, $id / 1000000, $id / 10000, $id);
	$xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX2, $id / 1000000, $id / 10000, $id) unless (-e $xmlfile);
	$xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $SF_DIR_PREFFIX5, $id / 1000000, $id / 10000, $id) unless (-e $xmlfile);
    }

    return &extract_sentences_from_standard_format($query, $xmlfile, $opt);
}

sub extract_sentences_from_standard_format {
    my($query, $xmlfile, $opt) = @_;

    if ($opt->{verbose}) {
	print "extract from $xmlfile.\n";
	print "option:\n";
	print Dumper($opt) . "\n";
    }

    my $content;
    open(READER,"zcat $xmlfile |") or die "$!";
    binmode(READER, ':utf8');
    while (<READER>) {
	$content .= $_;
    }
    close(READER);

    return &extract_sentences_from_content($query, $content, $opt);
}
    
sub extract_sentences_from_content {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $indexer = new Indexer();
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $in_title = 0;
    foreach my $line (split(/\n/, $content)) {
	$line .= "\n";
	if ($opt->{discard_title}) {
	    # タイトルはスニッペッツの対象としない
	    if ($line =~ /<Title [^>]+>/) {
		$in_title = 1;
	    } elsif ($line =~ /<\/Title>/ || $line =~ /<\/Header>/) {
		$in_title = 0;
	    }
	}
	next if ($in_title > 0);
	next if ($line =~ /^!/ && !$opt->{syngraph});

	$annotation .= $line;
	if ($line =~ m!</Annotation>!) {
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;
		my $indice = ($opt->{syngraph}) ? $indexer->makeIndexfromSynGraph($result) : $indexer->makeIndexFromKNPResult(new KNP::Result($result));
		my ($num_of_queries, $num_of_types) = &calculate_score($query, $indice, $opt);

		my $sentence = {
		    rawstring => undef,
		    score => 0,
		    smoothed_score => 0,
		    words => {},
		    dpnds => {},
		    surfs => [],
		    reps => [],
		    sid => $sid,
		    number_of_included_queries => $num_of_queries,
		    number_of_included_query_types => $num_of_types
		};

		$sentence->{result} = $result if ($opt->{keep_result});

		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result):  &make_word_list($result);

		my $num_of_whitespace_cdot_comma = 0;
		foreach my $w (@{$word_list}) {
		    my $surf = $w->{surf};
		    my $reps = $w->{reps};
		    $num_of_whitespace_cdot_comma++ if ($surf =~ /　|・|，|、|＞|−|｜|／/);

		    $sentence->{rawstring} .= $surf;
		    push(@{$sentence->{surfs}}, $surf);
		    push(@{$sentence->{reps}}, $w->{reps});
		}

		my $length = scalar(@{$sentence->{surfs}});
		$length = 1 if ($length < 1);
		my $score = $sentence->{number_of_included_query_types} * $sentence->{number_of_included_queries} * log($length);
		$sentence->{score} = $score;
		$sentence->{smoothed_score} = $score;
		$sentence->{length} = $length;
		$sentence->{num_of_whitespaces} = $num_of_whitespace_cdot_comma;

		push(@sentences, $sentence);
#		print encode('euc-jp', $sentence->{rawstring}) . " (" . $num_of_whitespace_cdot_comma . ") is SKIPPED.\n";
	    }
	    $sid++;
	    $annotation = '';
	}
    }

    my $window_size = $opt->{window_size};
    my $size = scalar(@sentences);
    for (my $i = 0; $i < scalar(@sentences); $i++) {
	my $s = $sentences[$i];
	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i - $j - 1;
	    last if ($k < 0);
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}

	for (my $j = 0; $j < $window_size; $j++) {
	    my $k = $i + $j + 1;
	    last if ($k > $size - 1);
	    $sentences[$k]->{smoothed_score} += ($s->{score} / (2 ** ($j + 1)));
	}
    }

    return \@sentences;
}

sub calculate_score {
    my ($query, $indice, $opt) = @_;

    my $num_of_queries = 0;
    my %matched_queries = ();
    my %buf;
    foreach my $idx (@$indice) {
	$buf{$idx->{midashi}}++;
    }

    for (my $q = 0; $q < scalar(@{$query}); $q++) {
	my $qk = $query->[$q];
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		if (exists($buf{$k})) {
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		}
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		if (exists($buf{$k})) {
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		}
	    }
	}
    }

    return ($num_of_queries, scalar(keys %matched_queries));
}

sub make_word_list {
    my ($sent) = @_;

    my @words;
    foreach my $line (split(/\n/,$sent)){
	next if ($line =~ /^\* \-?\d/);
	next if ($line =~ /^!/);
	next if ($line =~ /^S\-ID/);

	unless ($line =~ /^\+ (\-?\d+)([a-zA-Z])/){
	    next if ($line =~ /^(\<|\@|EOS)/);
	    next if ($line =~ /^\# /);
	    
	    my @m = split(/\s+/, $line);
	    
	    my $surf = $m[0];
	    my $midashi = "$m[2]/$m[1]";
	    my %reps = ();
	    ## 代表表記の取得
	    if ($line =~ /\<代表表記:([^>]+)\>/) {
		$midashi = $1;
	    }
	    
	    $reps{&toUpperCase_utf8($midashi)} = 1;
	    
	    ## 代表表記に曖昧性がある場合は全部保持する
	    ## ただし表記・読みが同一の代表表記は区別しない
	    ## ex) 日本 にっぽん 日本 名詞 6 地名 4 * 0 * 0 "代表表記:日本/にほん" <代表表記:日本/にほん><品曖><ALT-日本-にほん-日本-6-4-0-0-"代表表記:日本/にほん"> ...
	    my $lnbuf = $line;
	    while ($line =~ /\<ALT(.+?)\>/) {
		$line = "$'";
		my $alt_cont = $1;
		if ($alt_cont =~ /代表表記:(.+?)(?: |\")/) {
		    my $midashi = $1;
		    $reps{&toUpperCase_utf8($midashi)} = 1;
		} elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
		    my $midashi = "$3/$2";
		    $reps{&toUpperCase_utf8($midashi)} = 1;
		}
	    }
	    $line = $lnbuf;
	    
	    my @reps_array = sort keys %reps;
	    my $word = {
		surf => $surf,
		reps => \@reps_array,
		isContentWord => 0
	    };

	    push(@words, $word);

	    if($line =~ /\<意味有\>/){
		next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
		$word->{isContentWord} = 1;
	    }
	} # end of else
    } # end of foreach my $line (split(/\n/,$sent))

    return \@words;
}

sub make_word_list_syngraph {
    my ($synresult) = @_;

    my @words;
    my $start = 0;
    my $bnstcnt = -1;
    my $wordcnt = 0;
    my %bnst2pos = ();
    foreach my $line (split(/\n/, $synresult)) {
	next if($line =~ /^!! /);
	next if($line =~ /^\* /);
	next if($line =~ /^# /);
	next if($line =~ /EOS/);

	if ($line =~ /^\+ /) {
	    $bnstcnt++;
	    next;
	}

	unless ($line =~ /^! /) {
	    my @m = split(/\s+/, $line);
	    my $surf = $m[0];
	    my $word = {
		surf => $surf,
		reps => [],
		isContentWord => 0
	    };
	    $word->{isContentWord} = 1 if (index($line, '<意味有>') > 0);

	    $words[$wordcnt] = $word;
	    push(@{$bnst2pos{$bnstcnt}}, $wordcnt);
	    $wordcnt++;
	} else {
	    my ($dumy, $bnstId, $syn_node_str) = split(/ /, $line);
	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $sid = $1;
		$sid = $1 if ($sid =~ m!^([^/]+)/!);
		
		my $features = $3;
		$features = "$`$'" if ($features =~ /\<上位語\>/); # <上位語>を削除
		$features =~ s/<下位語数:\d+>//; # <下位語数:(数字)>を削除

		foreach my $bid (split(/,/, $bnstId)) {
		    foreach my $pos (@{$bnst2pos{$bid}}) {
			next if ($words[$pos]->{isContentWord} < 1);
			push(@{$words[$pos]->{reps}}, "$sid$features");
		    }
		}
	    }
	} # end of else
    } # end of foreach my $line (split(/\n/,$sent))

    return \@words;
}


## 全角小文字アルファベット(utf8)を全角大文字アルファベットに変換(utf8)
sub toUpperCase_utf8 {
    my($str) = @_;
    my @cbuff = ();
    my @ch_codes = unpack("U0U*", $str);
    for(my $i = 0; $i < scalar(@ch_codes); $i++){
	my $ch_code = $ch_codes[$i];
	unless(0xff40 < $ch_code && $ch_code < 0xff5b){
	    push(@cbuff, $ch_code);
	}else{
	    my $uppercase_code = $ch_code - 0x0020;
	    push(@cbuff, $uppercase_code);
	}
    }
    return pack("U0U*",@cbuff);
}

1;
