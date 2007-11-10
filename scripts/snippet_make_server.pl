#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use Encode;
use Getopt::Long;
use MIME::Base64;
use IO::Socket;
use Storable;

my $MAX_NUM_OF_WORDS_IN_SNIPPET = 100;
my $DIR_PREFFIX = '/data/sfs';

my (%opt);
GetOptions(\%opt, 'help', 'port=s', 'verbose');

if (!$opt{port} || $opt{help}) {
    print "Usage\n";
    print "$0 -idxdir idxdir_path -dlengthdbdir doc_lengthdb_dir_path -port PORT_NUMBER\n";
    exit;
}

&main();

sub main {
    my $listening_socket = IO::Socket::INET->new(
	LocalPort => $opt{port},
	Listen    => SOMAXCONN,
	Proto     => 'tcp',
	Reuse     => 1);

    unless ($listening_socket) {
	my $host = `hostname`; chop($host);
	die "Cannot listen port No. $opt{port} on $host. $!\n";
	exit;
    }

    # 問い合わせを待つ
    while (1) {
	my $new_socket = $listening_socket->accept();
	my $client_sockaddr = $new_socket->peername();
	my($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
	my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
	my $client_ip = inet_ntoa($client_iaddr);
	
	select($new_socket); $|=1; select(STDOUT);
	
	my $pid;
	if ($pid = fork()) {
	    $new_socket->close();
	    wait;
	} else {
	    print "cactch query\n" if ($opt{verbose});

	    select($new_socket); $|=1; select(STDOUT);

	    # クエリの受信
	    my $buff;
	    while (<$new_socket>) {
		last if ($_ eq "EOQ\n");
		$buff .= $_;
	    }
	    my $query = Storable::thaw(decode_base64($buff));
	    print "restore query\n" if ($opt{verbose});

	    # スニペッツを生成する文書IDの取得
	    $buff = undef;
	    while (<$new_socket>) {
		last if ($_ eq "EOD\n");
		$buff .= $_;
	    }
	    my $dids = Storable::thaw(decode_base64($buff));
	    print "restore dids\n" if ($opt{verbose});

	    # スニペッツの生成
	    my %result = ();
	    print "begin with snippet creation\n" if ($opt{verbose});
	    foreach my $did (@{$dids}) {
		my $filepath = sprintf("%s/x%03d/x%05d/%09d.xml", $DIR_PREFFIX, $did / 1000000, $did / 10000, $did);
		$result{$did} = &SnippetMaker::extractSentencefromKnpResult($query->{keywords}, $filepath);
	    }
	    print "finish of snippet creation\n" if ($opt{verbose});

	    # スニペッツの送信
	    print $new_socket encode_base64(Storable::freeze(\%result), "") , "\n";
	    print $new_socket "END\n";
	    
	    $new_socket->close();
	    exit;
	}
    }
}

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
