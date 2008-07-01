package SnippetMaker;

# $Id$

use strict;
use Encode qw(encode decode from_to);
use utf8;

use KNP;
use Indexer;
use Configure;
use StandardFormatData;
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

    if ($opt->{kwic}) {
	return &extract_sentences_from_content_for_kwic($query, $content, $opt);
    } else {
	return &extract_sentences_from_content($query, $content, $opt);
    }	
}

sub isMatch {
    my ($listQ, $listS) = @_;

    use Data::Dumper;
    # print Dumper($listQ) . "\n";

    my $end = -1;
    my $matchQ = 0;
    for (my $i = 0; $i < scalar(@$listS); $i++) {
	for (my $j = 0; $j < scalar(@$listQ); $j++) {
	    # クエリレベルで代表表記がマッチしたか
	    $matchQ = 0;
	    # 単語レベルで代表表記がマッチしたか
	    my $matchW = 0;
	    foreach my $rep (keys %{$listS->[$i + $j]}) {
		# print $rep . " ";
		if (exists $listQ->[$j]{$rep}) {
		    $end = $i + $j;
		    $matchW = 1;
		    # print "*";
		    last;
		}
	    }
	    # print "\n";
	    # マッチしなければ（文の方の）次の単語へ
	    unless ($matchW) {
		$end = -1;
		last;
	    }
	    $matchQ = 1;
	}

	if ($matchQ) {
	    return (1, $i, $end + 1);
	}
    }

    return (0, -1, -1);
}
    
sub extract_sentences_from_content_for_kwic {
    my ($query, $content, $opt) = @_;

    my $sfdat = new StandardFormatData(\$content, $opt);
    my @sbuf;
    my $title = $sfdat->getTitle();
    my $queryString = $query->[$opt->{kwic_keyword_index}]{rawstring}; # kwic_keyword_index番目のqueryをkeywordとして用いる  (定義されていない場合は0番目、つまり初期クエリになる)

    my ($repnameList_q, $surfList_q) = &make_repname_list($query->[$opt->{kwic_keyword_index}]{knp_result}->all());

    my $sentences = $sfdat->getSentences();
    for (my $i = 0; $i < scalar(@$sentences); $i++) {
	my $s = $sentences->[$i];
	my ($repnameList_s, $surfList_s) = &make_repname_list($s->{annotation}, $opt);
	my ($flag, $from, $end) = &isMatch($repnameList_q, $repnameList_s);
	if ($flag) {
	    my $keyword;
	    my $contextL;
	    my $contextR;
	    for (my $j = 0; $j < scalar(@$surfList_s); $j++) {
		if ($j < $from) {
		    $contextL .= $surfList_s->[$j];
		}
		elsif ($j > $end - 1) {
		    $contextR .= $surfList_s->[$j];
		}
		else {
		    $keyword .=  $surfList_s->[$j];
		}
	    }

	    # 左右のコンテキストを指定された幅に縮める

	    my @contextsR;
	    my $lengthR = length($contextR);
	    if ($lengthR > $opt->{kwic_window_size}) {
		push(@contextsR, substr($contextR, 0, $opt->{kwic_window_size}));
	    } else {
		push(@contextsR, $contextR);

		# $opt->{kwic_window_size} に満たない場合は、後続の文を取得する
		my $j = $i + 1;
		while ($j < scalar(@$sentences)) {
		    my $afterS = $sentences->[$j++]->{rawstring};
		    my $length = length($afterS);
		    if ($length + $lengthR > $opt->{kwic_window_size}) {
			my $diff = $opt->{kwic_window_size} - $lengthR;
			push(@contextsR, substr($afterS, 0, $diff));
			last;
		    } else {
			$lengthR += $length;
			push(@contextsR, $afterS);
		    }
		}
	    }

	    my @contextsL;
	    my $lengthL = length($contextL);
	    if ($lengthL > $opt->{kwic_window_size}) {
		my $offset = length($contextL) - $opt->{kwic_window_size};
		$offset = 0 if ($offset < 0);
		push(@contextsL, substr($contextL, $offset, $opt->{kwic_window_size}));
	    } else {
		push(@contextsL, $contextL);
		
		# $opt->{kwic_window_size} に満たない場合は、前方の文を取得する
		my $j = $i - 1;
		while ($j > -1) {
		    my $beforeS = $sentences->[$j]->{rawstring};
		    $j--;

		    my $length = length($beforeS);
		    if ($length + $lengthL > $opt->{kwic_window_size}) {
			my $diff = $opt->{kwic_window_size} - $lengthL;
			my $offset = $length - $diff;
			unshift(@contextsL, substr($beforeS, $offset, $diff));
			last;
		    } else {
			$lengthL += $length;
			unshift(@contextsL, $beforeS);
		    }
		}
	    }

	    # ソート用に逆右コンテキストを取得する
	    my $InvertedContextL = reverse(join("", @contextsL));
	    push(@sbuf, {title => $title->{rawstring},
			 rawstring => $s->{rawstring},
			 contextR => join('', @contextsR),
			 contextL => join('', @contextsL),
			 contextsR => \@contextsR,
			 contextsL => \@contextsL,
			 keyword => $keyword,
			 InvertedContextL => $InvertedContextL
		 });
	}
# 	if (my ($s->{rawstring} =~ /$queryString/) {
# 	    my $contextL = "$`";
# 	    my $contextR = "$'";
# 	    next if ($contextL eq '' && $contextR eq '');

# 	    $contextR = substr($contextR, 0, $opt->{kwic_window_size});

# 	    my $offset = length($contextL) - $opt->{kwic_window_size};
# 	    $offset = 0 if ($offset < 0);
# 	    $contextL = substr($contextL, $offset, $opt->{kwic_window_size});

# 	    my $InvertedContextL = reverse($contextL);
# 	    push(@sbuf, {title => $title->{rawstring},
# 			 rawstring => $s->{rawstring},
# 			 contextR => $contextR,
# 			 contextL => $contextL,
# 			 InvertedContextL => $InvertedContextL
# 		 });
# 	}
    }

    return \@sbuf;
}

sub make_repname_list {
    my ($knpresult, $opt) = @_;

    my @repnameList;
    my @surfList;
    foreach my $line (split(/\n/,$knpresult)){
	next if ($line =~ /^\*/);
	next if ($line =~ /^\+/);
	next if ($line =~ /^!/);
	next if ($line =~ /^EOS/);
	next if ($line =~ /^\# /);

	my @m = split(/\s+/, $line);
	my $surf = $m[0];
	my $katsuyou = $m[9];
	my $hinshi = $m[3];
#	my $midashi = "$m[2]/$m[1]";
	my $midashi = $m[2];
	my %reps = ();
	# 代表表記の取得
# 	if ($line =~ /\<代表表記:([^>]+)\>/) {
# 	    $midashi = $1;
# 	}
	$reps{&toUpperCase_utf8($midashi)} = 1;

	# 代表表記に曖昧性がある場合は全部保持する
	# ただし表記・読みが同一の代表表記は区別しない
	# ex) 日本 にっぽん 日本 名詞 6 地名 4 * 0 * 0 "代表表記:日本/にほん" <代表表記:日本/にほん><品曖><ALT-日本-にほん-日本-6-4-0-0-"代表表記:日本/にほん"> ...
# 	my $lnbuf = $line;
# 	while ($line =~ /\<ALT(.+?)\>/) {
# 	    $line = "$'";
# 	    my $alt_cont = $1;
# 	    if ($alt_cont =~ /代表表記:(.+?)(?: |\")/) {
# 		my $midashi = $1;
# 		$reps{&toUpperCase_utf8($midashi)} = 1;
# 	    } elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
# 		my $midashi = "$3/$2";
# 		$reps{&toUpperCase_utf8($midashi)} = 1;
# 	    }
# 	}
# 	$line = $lnbuf;

	if ($opt->{is_phrasal_search}) {
	    if ($hinshi eq '動詞') {
		my %new_reps;
		foreach my $k (keys %reps) {
		    $new_reps{$k . ":$katsuyou"} = $reps{$k};
		}
		%reps = %new_reps;
	    }
	}

	push(@repnameList, \%reps);
	push(@surfList, $surf);
    } # end of foreach my $line (split(/\n/,$sent))

    return (\@repnameList, \@surfList);
}

sub extract_sentences_from_content {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $indexer = new Indexer({ignore_yomi => $opt->{ignore_yomi}});
    my @sentences = ();
    my %sbuff = ();
    my $sid = 0;
    my $in_title = 0;
    my $in_link_tag = 0;
    my $in_meta_tag = 0;
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

	$in_link_tag = 1 if ($line =~ /<InLinks>/);
	$in_link_tag = 0 if ($line =~ /<\/InLinks>/);
	$in_link_tag = 1 if ($line =~ /<OutLinks>/);
	$in_link_tag = 0 if ($line =~ /<\/OutLinks>/);

	$in_meta_tag = 1 if ($line =~ /<Description>/);
	$in_meta_tag = 0 if ($line =~ /<\/Description>/);
	$in_meta_tag = 1 if ($line =~ /<Keywords>/);
	$in_meta_tag = 0 if ($line =~ /<\/Keywords>/);

	next if ($in_link_tag || $in_meta_tag);

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

		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result, $opt);

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

    return \@sentences;
}

sub extract_sentences_from_content_old {
    my($query, $content, $opt) = @_;

    my $annotation;
    my $indexer = new Indexer({ignore_yomi => $opt->{ignore_yomi}});
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

		my $word_list = ($opt->{syngraph}) ?  &make_word_list_syngraph($result) :  &make_word_list($result, $opt);

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

    return \@sentences;
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
    my ($sent, $opt) = @_;

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
	    $midashi =~ s/\/.+// if ($opt->{ignore_yomi});

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
		    $midashi =~ s/\/.+// if ($opt->{ignore_yomi});
		    $reps{&toUpperCase_utf8($midashi)} = 1;
		} elsif ($alt_cont =~ /\-(.+?)\-(.+?)\-(.+?)\-/) {
		    my $midashi = ($opt->{ignore_yomi}) ? $3 : "$3/$2";
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
	    # 準内容語もハイライトの要素とする
	    # 準内容語の部分に、内容語を代入する
	    # 薬 の 効果 的な 飲み 方 → 薬 の 効果 効果 飲み 飲み
	    $word->{isContentWord} = 1 if ($line =~ /(<意味有>|<準?内容語>)/);

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
