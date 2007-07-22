package SnippetMaker;

use strict;
use Encode qw(encode decode from_to);
use utf8;

use Indexer;
use Data::Dumper;


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

    my $buff;
    my $indexer = new Indexer();
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
		    
		    $sentence->{score} = $sentence->{score} * log(scalar(@{$sentence->{surfs}}));
		    push(@sentences, $sentence);
		}
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
    while (<READER>) {
	$buff .= $_;
	if ($_ =~ m!</Annotation>!) {
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"Knp\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
		my $knpresult = $1;

		my $score = 0;
		my $indice = $indexer->makeIndexfromKnpResult($knpresult);

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
			score => $score
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
			$sentence->{score} = $sentence->{score} * log(scalar(@{$sentence->{surfs}}));
			push(@sentences, $sentence);
			$sbuff{$sentence->{rawstring}} = 1;
		    }
		}
	    } # end of if
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sentences;
}

sub make_word_list {
    my ($sent) = @_;

    my @words;
    foreach my $line (split(/\n/,$sent)){
	next if($line =~ /^\* \-?\d/);

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
	    if ($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>(<[^>]+>)*$!) {
		my $sid = $1;
		my $features = $3;
		$sid = $1 if ($sid =~ m!^([^/]+)/!);
		
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
