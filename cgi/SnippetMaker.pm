package SnippetMaker;

use strict;
use Encode qw(encode decode from_to);
use utf8;

use KNP;
use Indexer;
use Configure;
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

my $CONFIG = Configure::get_instance();

sub extract_sentences_from_ID {
    my($query, $id, $opt) = @_;

    my $dir_prefix = ($opt->{syngraph}) ? $CONFIG->{DIR_PREFIX_FOR_SFS_W_SYNGRAPH} : $CONFIG->{DIR_PREFIX_FOR_SFS};
    my $xmlfile = sprintf("%s/x%03d/x%05d/%09d.xml.gz", $dir_prefix, $id / 1000000, $id / 10000, $id);

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

	$sid = $1 if ($line =~ m!<S .+ Id="(\d+)"!);
	$sid = 0 if ($line =~ m!<Title !);

	if ($line =~ m!</Annotation>!) {
	    if ($annotation =~ m/<Annotation Scheme=\".+?\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/) {
		my $result = $1;
		my $indice = ($opt->{syngraph}) ? $indexer->makeIndexfromSynGraph($result, undef, $opt) : $indexer->makeIndexFromKNPResult($result, $opt);
		my ($num_of_queries, $num_of_types, $including_all_indices) = &calculate_score($query, $indice, $opt);

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
		    number_of_included_query_types => $num_of_types,
		    including_all_indices => $including_all_indices
		};

		$sentence->{result} = $result if ($opt->{keep_result});

		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result);

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

    if ($opt->{kwic}) {
	my @buf;
	my $keyword = $query->[0]{words};
	foreach my $s (@sentences) {
	    next unless ($s->{including_all_indices});

	    my $pos = 0;
	    my $reps = $s->{reps};
	    for (my $j = 0; $j < scalar(@{$reps}); $j++) {
		my $match = -1;
		for (my $i = 0; $i < scalar(@{$keyword}); $i++) {

		  OUT_OF_MATCHING_LOOP:
		    foreach my $srep (@{$reps->[$j + $i]}) {
			foreach my $krep (@{$keyword->[$i]}) {
			    if ($krep->{string} eq $srep) {
				$match = $i + $j;
				last OUT_OF_MATCHING_LOOP;
			    }
			}
		    }

		    last if ($match < 0);
		}

		if ($match > -1) {
		    $s->{startOfKeyword} = $j;
		    $s->{endOfKeyword} = $match;
		    last;
		}
	    }
	    push(@buf, $s);
	}
	return \@buf;
    } else {
	return \@sentences;
    }
}

sub calculate_score {
    my ($query, $indice, $opt) = @_;

    my $num_of_queries = 0;
    my %matched_queries = ();
    my %buf;
    foreach my $idx (@$indice) {
	$buf{$idx->{midasi}}++;
    }

    if ($opt->{debug}) {
	print "index terms in a sentence\n";
	print Dumper (\%buf) . "\n";
	print "-----\n";
    }

    my $including_all_indices = 1;
    for (my $q = 0; $q < scalar(@{$query}); $q++) {
	my $qk = $query->[$q];
	foreach my $reps (@{$qk->{words}}) {
	    my $flag = 0;
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		$k =~ s/(a|v)$// unless ($opt->{string_mode});
		print $k . " is exists? -> " if ($opt->{debug});
		if (exists($buf{$k})) {
		    print "true.\n" if ($opt->{debug});
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		    $flag = 1;
		} else {
		    print "false.\n" if ($opt->{debug});
		}
	    }

	    $including_all_indices = 0 unless ($flag);
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    my $flag = 0;
	    foreach my $rep (@{$reps}) {
		my $k = $rep->{string};
		$k =~ s/(a|v)//g unless ($opt->{string_mode});
		print $k . " is exists? -> " if ($opt->{debug});
		if (exists($buf{$k})) {
		    print "true.\n" if ($opt->{debug});
		    $num_of_queries += $buf{$k};
		    $matched_queries{$k}++;
		    $flag = 1;
		} else {
		    print "false.\n" if ($opt->{debug});
		}
	    }

	    $including_all_indices = 0 unless ($flag);
	}
    }
    print "=====\n" if ($opt->{debug});
    return ($num_of_queries, scalar(keys %matched_queries), $including_all_indices);
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

	    if ($line =~ /(<意味有>|<内容語>)/) {
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
	    $word->{isContentWord} = 1 if ($line =~ /(<意味有>|<内容語>)/);

	    $words[$wordcnt] = $word;
	    push(@{$bnst2pos{$bnstcnt}}, $wordcnt);
	    $wordcnt++;
	} else {
	    my ($dumy, $bnstId, $syn_node_str) = split(/ /, $line);
	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>((<[^>]+>)*)$!) {
		my $sid = $1;
		my $features = $3;
		$sid = $1 if ($sid =~ m!^([^/]+)/!);

		# 文法素性の削除
		$features =~ s/<可能>//;
		$features =~ s/<尊敬>//;
		$features =~ s/<受身>//;
		$features =~ s/<使役>//;
		$features =~ s/<上位語>//;

		# <下位語数:(数字)>を削除
		$features =~ s/<下位語数:\d+>//;

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
