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

    my @sent_objs = ();
    if(-e $xmlpath){
	open(READER, $xmlpath);
    }else{
	$xmlpath .= ".gz";
	open(READER,"zcat $xmlpath |");
    }

    my $buff;
    my $indexer = new Indexer();
    while(<READER>){
	$buff .= $_;
	if($_ =~ m!</Annotation>!){
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"SynGraph\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
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

		my $syn_idxs = $indexer->makeIndexfromSynGraph($synresult);
		foreach my $s (keys %{$syn_idxs}){
		    if(index($s, '->') > 0){
			$sent_obj->{dpnds}->{$s} = 0 unless(exists($sent_obj->{dpnds}->{$s}));
			$sent_obj->{dpnds}->{$s} += $syn_idxs->{$s}->{freq};
		    }
		}
		
		foreach my $line (split(/\n/, $synresult)) {
		    next if($line =~ /^!! /);
		    next if($line =~ /^\* /);
		    next if($line =~ /^# /);
		    next if($line =~ /EOS/);
		    if($line =~ /^\+ /){
			$start = $count;
			$bnstcnt++;
			next;
		    }

		    unless($line =~ /^! /){
			my @m = split(/\s+/, $line);
			my $surf = $m[0];
			my $word = $m[2];
			my %synNodes = ();
			my $mrph_obj = {surf => undef,
					reps => undef,
					isContentWord => 0
			};

			$sent_obj->{rawstring} .= $surf;
			$mrph_obj->{surf} = $surf;
			$mrph_obj->{reps} = \%synNodes;
			$mrph_obj->{isContentWord} = 1 if(index($line, '<意味有>') > 0);

			push(@{$sent_obj->{list}}, $mrph_obj);
			push(@{$bnstmap{$bnstcnt}}, $count++);
		    }else{
			my($dumy, $bnstId, $syn_node_str) = split(/ /, $line);
			if($line =~ m!<SYNID:([^>]+)><スコア:((?:\d|\.)+)>(<[^>]+>)*$!){
			    my $sid = $1;
			    my $score = $2;
			    my $features = $3;
			    if($sid =~ m!^([^/]+)/!){
				$sid = $1;
			    }

			    foreach my $bid (split(/,/, $bnstId)){
				foreach my $i (@{$bnstmap{$bid}}){
				    my $m = $sent_obj->{list}->[$i];
				    next if($m->{isContentWord} < 1);

				    $m->{reps}->{"$sid$features"} = $score;
				    $sent_obj->{words}->{"$sid$features"} = $score;
				}
			    }
			}else{
			}
		    }
		}
		
		my $score = 0;
		foreach my $k (keys %{$query->{words}}){
		    next if($k =~ /^(?:が|の|に|を)$/);
		    $score += $sent_obj->{words}->{$k} if(exists($sent_obj->{words}->{$k}));
		}

		foreach my $k (keys %{$query->{dpnds}}){
		    if(exists($sent_obj->{dpnds}->{$k})){
			$score += $sent_obj->{dpnds}->{$k}
		    }
		}

		if($score > 0){
		    $sent_obj->{score} = ($score * log(length($sent_obj->{rawstring})));
		    push(@sent_objs, $sent_obj);
		}
	    } # end of if
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sent_objs;
}

sub extractSentencefromKnpResult {
    my($query, $xmlpath) = @_;

    my @sent_objs = ();
    if(-e $xmlpath){
	open(READER, $xmlpath);
    }else{
	$xmlpath .= ".gz";
	open(READER,"zcat $xmlpath |");
    }

    my $buff;
    my $indexer = new Indexer();
    while(<READER>){
	$buff .= $_;
	if($_ =~ m!</Annotation>!){
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"Knp\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
		my %words = ();
		my %dpnds = ();
		my @temp2 = ();
		my $knpresult = $1;
		my $sent_obj = {rawstring => undef,
				words => \%words,
				dpnds => \%dpnds,
				list  => \@temp2,
				score => 0.0
		};

		my $dpnd_idxs = $indexer->makeIndexfromKnpResult($knpresult);
		foreach my $d (keys %{$dpnd_idxs}){
		    $d = &h2z_ascii($d);
		    $sent_obj->{dpnds}->{$d} = 0 unless(exists($sent_obj->{dpnds}->{$d}));
		    $sent_obj->{dpnds}->{$d} += $dpnd_idxs->{$d}->{freq};
		}

		foreach my $line (split(/\n/, $knpresult)){
		    next if($line =~ /^\* /);
		    next if($line =~ /^\+ /);
		    next if($line =~ /EOS/);
		    
		    my @m = split(/\s+/, $line);
		    my $surf = $m[0];
		    my $word = $m[2];
		    my $mrph_obj = {surf => undef,
				    reps => undef
		    };

		    $sent_obj->{rawstring} .= $surf;
		    $mrph_obj->{surf} = $surf;
#		    if($line =~ /\<意味有\>/){
#			next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
			
			my %reps = ();
			## 代表表記の取得
			if($line =~ /代表表記:(.+?)\//){
			    $word = $1;
			}

			$reps{$word} = 1;
			## 代表表記に曖昧性がある場合は全部保持する
			while($line =~ /\<ALT(.+?)\>/){
			    $line = "$'";
			    if($1 =~ /代表表記:(.+?)\//){
				$reps{$word} = 1;
			    }
			}

			my $size = scalar(keys %reps);
			foreach my $w (keys %reps){
			    $w = &h2z_ascii($w);
			    $sent_obj->{words}->{$w} = 0 unless(exists($sent_obj->{words}->{$w}));
			    $sent_obj->{words}->{$w} += (1 / $size);
			}
			$mrph_obj->{reps} = \%reps;
#		    }

		    push(@{$sent_obj->{list}}, $mrph_obj);
		}
			    
		my $score = 0;
		foreach my $k (keys %{$query->{words}}){
		    next if($k =~ /^(?:が|の|に|を)$/);
		    $score += $sent_obj->{words}->{$k} if(exists($sent_obj->{words}->{$k}));
		}

		foreach my $k (keys %{$query->{dpnds}}){
		    if(exists($sent_obj->{dpnds}->{$k})){
			$score += $sent_obj->{dpnds}->{$k}
		    }
		}

		if($score > 0){
		    $sent_obj->{score} = ($score * log(length($sent_obj->{rawstring})));
		    push(@sent_objs, $sent_obj);
		}
	    } # end of if
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sent_objs;
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
