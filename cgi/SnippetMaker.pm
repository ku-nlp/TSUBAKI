package SnippetMaker;

use strict;
use Encode qw(encode decode from_to);
use utf8;

use Indexer;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;



sub makeSnippetfromDocument {
    my ($query_obj, $filepath) = @_;
    my $sent_objs = &extractSentence($query_obj, $filepath);
    return &makeSnippetsfromSentences($query_obj, $sent_objs);
}

sub makeSnippetfromSentences {
    my ($query_obj, $sent_objs) = @_;

    my $snippet = {rawstring => undef, words => undef, dpnds => undef};
    my %words = ();
    my $length = 0;
    foreach my $sent_obj (sort {$b->{score} <=> $a->{score}} @{$sent_objs}){
	my @mrph_objs = @{$sent_obj->{list}};
	foreach my $m (@mrph_objs){
	    my $surf = $m->{surf};
	    my $reps = $m->{reps};

	    foreach my $k (keys %{$reps}){
		$words{$k} += $reps->{$k};
	    }

	    $snippet->{rawstring} .= $surf;
	    $length += length($surf);
	    if($length > 200){
		$snippet->{rawstring} .= " ...";
		last;
	    }
	}
	last if($length > 200);
    }

    $snippet->{words} = \%words;

    return $snippet;
}

sub extractSentencefromSynGraphResult {
    my($query, $xmlpath) = @_;

    my @sentences = ();
    if (-e $xmlpath) {
	open(READER, $xmlpath);
    } else {
	$xmlpath .= ".gz";
	open(READER, "zcat $xmlpath |");
    }

    my $sid = 0;
    my $buff;
    my $indexer = new Indexer();
    my %sbuff = ();
    while (<READER>) {
	$buff .= $_;
	if ($_ =~ m!</Annotation>!) {
	    $buff = decode('utf8', $buff);
	    if ($buff =~ m/<Annotation Scheme=\"SynGraph\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my %words = ();
		my %dpnds = ();
		my @temp2 = ();
		my $synresult = $1;
		my $sent_obj = {rawstring => undef,
				words => \%words,
				dpnds => \%dpnds,
				list  => \@temp2,
				score => 0.0
		};

		my $start = 0;
		my $count = 0;
		my $bnstcnt = -1;
		my %bnstmap = ();

		my $score = 0;
		my $indice = $indexer->makeIndexfromSynGraph($synresult);

		foreach my $qk (@{$query}) {
		    foreach my $reps (@{$qk->{words}}) {
			foreach my $rep (@{$reps}) {
			    if (exists($indice->{$rep->{string}})) {
				$score += $indice->{$rep->{string}}{freq};
			    }
			}
		    }

		    foreach my $reps (@{$qk->{dpnds}}) {
			foreach my $rep (@{$reps}) {
			    if (exists($indice->{$rep->{string}})) {
				$score += $indice->{$rep->{string}}{freq};
			    }
			}
		    }
		}

		if ($score > 0) {
		    my $sentence = {
			rawstring => undef,
			words => {},
			dpnds => {},
			surfs => [],
			reps => [],
			sid => $sid,
			score => $score
		    };

		    my $word_list = &make_word_list_syngraph($synresult);

		    foreach my $w (@{$word_list}) {
			my $surf = $w->{surf};
			my $reps = $w->{reps};

			$sentence->{rawstring} .= $surf;
			push(@{$sentence->{surfs}}, $surf);
			push(@{$sentence->{reps}}, $w->{reps});
		    }

		    $sentence->{rawstring} =~ s/^S\-ID:\d+//;
		    unless (exists($sbuff{$sentence->{rawstring}})) {
			$sentence->{score} = $sentence->{score} * log(scalar(@{$sentence->{surfs}}));
			push(@sentences, $sentence);
			$sbuff{$sentence->{rawstring}} = 1;
		    }
		}
		$sid++;
	    } # end of if
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sentences;
}


sub extractSentencefromKnpResult {
    my($query, $xmlpath) = @_;

    if (-e $xmlpath) {
	open(READER, $xmlpath) or die;
    } else {
	$xmlpath .= ".gz";
	open(READER,"zcat $xmlpath |") or die;
    }

    my $buff;
    my $indexer = new Indexer();
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    while (<READER>) {
	$buff .= $_;
	if ($_ =~ m!</Annotation>!) {
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"Knp\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
		my $knpresult = $1;
		my $score = 0;
		my $indice = $indexer->makeIndexfromKnpResult($knpresult);

		my %matched_queries = ();
		for (my $q = 0; $q < scalar(@{$query}); $q++) {
		    my $qk = $query->[$q];
		    foreach my $reps (@{$qk->{words}}) {
			foreach my $rep (@{$reps}) {
			    if (exists($indice->{$rep->{string}})) {
				$score += 1;# $indice->{$rep->{string}}{freq};
				$matched_queries{$q}++;
			    }
			}
		    }

		    foreach my $reps (@{$qk->{dpnds}}) {
			foreach my $rep (@{$reps}) {
			    if (exists($indice->{$rep->{string}})) {
				$score += 2; # * $indice->{$rep->{string}}{freq};
				$matched_queries{$q}++;
			    }
			}
		    }
		}

		if ($score > 0) {
		    my $sentence = {
			rawstring => undef,
			words => {},
			dpnds => {},
			surfs => [],
			reps => [],
			sid => $sid,
			score => $score,
			number_of_included_queries => scalar(keys %matched_queries)
		    };

		    my $word_list = &make_word_list($knpresult);

		    foreach my $w (@{$word_list}) {
			my $surf = $w->{surf};
			my $reps = $w->{reps};

			$sentence->{rawstring} .= $surf;
			push(@{$sentence->{surfs}}, $surf);
			push(@{$sentence->{reps}}, $w->{reps});
		    }
		    
		    unless (exists($sbuff{$sentence->{rawstring}})) {
			$sentence->{score} = $sentence->{number_of_included_queries} * $sentence->{score} * log(scalar(@{$sentence->{surfs}}));
			push(@sentences, $sentence);
			$sbuff{$sentence->{rawstring}} = 1;
		    }
		}
		$sid++;
	    } # end of if
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sentences;
}

my $SF_DIR_PREFFIX1 = "/data/sfs";
my $SF_DIR_PREFFIX2 = "/data/sfs_w_syn";
my $SF_DIR_PREFFIX3 = "/net2/nlpcf34/disk09/skeiji/sfs_w_syn";
my $SF_DIR_PREFFIX4 = "/net2/nlpcf34/disk03/skeiji/sfs_w_syn";

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
    }

    return &extract_sentences_from_standard_format($query, $xmlfile, $opt);
}

sub extract_sentences_from_standard_format {
    my($query, $xmlfile, $opt) = @_;

    open(READER,"zcat $xmlfile |") or die "$!";

    if ($opt->{verbose}) {
	print "extract from $xmlfile.\n";
	print "option:\n";
	print Dumper($opt) . "\n";
    }

    my $annotation;
    my $indexer = new Indexer();
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $in_title = 0;
    while (<READER>) {
	if ($opt->{discard_title}) {
	    # タイトルはスニッペッツの対象としない
	    if ($_ =~ /<Title [^>]+>/) {
		$in_title = 1;
	    } elsif ($_ =~ /<\/Title>/ || $_ =~ /<\/Header>/) {
		$in_title = 0;
	    }
	}
	next if ($in_title > 0);
	next if ($_ =~ /^!/ && !$opt->{syngraph});

	$annotation .= $_;
	if ($_ =~ m!</Annotation>!) {
#	    print encode('euc-jp', decode('utf8', $annotation));

	    $annotation = decode('utf8', $annotation);
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;
		my $indice = ($opt->{syngraph}) ? $indexer->makeIndexfromSynGraph($result) : $indexer->makeIndexfromKnpResult($result);
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
    close(READER);

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

sub h2z_ascii {
    my($string) = @_;
    $string =~ s/ａ/Ａ/g;
    $string =~ s/ｂ/Ｂ/g;
    $string =~ s/ｃ/Ｃ/g;
    $string =~ s/ｄ/Ｄ/g;
    $string =~ s/ｅ/Ｅ/g;
    $string =~ s/ｆ/Ｆ/g;
    $string =~ s/ｇ/Ｇ/g;
    $string =~ s/ｈ/Ｈ/g;
    $string =~ s/ｉ/Ｉ/g;
    $string =~ s/ｊ/Ｊ/g;
    $string =~ s/ｋ/Ｋ/g;
    $string =~ s/ｌ/Ｌ/g;
    $string =~ s/ｍ/Ｍ/g;
    $string =~ s/ｎ/Ｎ/g;
    $string =~ s/ｏ/Ｏ/g;
    $string =~ s/ｐ/Ｐ/g;
    $string =~ s/ｑ/Ｑ/g;
    $string =~ s/ｒ/Ｒ/g;
    $string =~ s/ｓ/Ｓ/g;
    $string =~ s/ｔ/Ｔ/g;
    $string =~ s/ｕ/Ｕ/g;
    $string =~ s/ｖ/Ｖ/g;
    $string =~ s/ｗ/Ｗ/g;
    $string =~ s/ｘ/Ｘ/g;
    $string =~ s/Y/Ｙ/g;
    $string =~ s/Z/Ｚ/g;

    return $string;
}

1;
