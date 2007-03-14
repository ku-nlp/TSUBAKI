package QueryParser;

# 検索クエリを内部形式に変換するモジュール

my $TOOL_HOME='/home/skeiji/local/bin';

use strict;
use Encode;
use utf8;

our @EXPORT = qw(parse);

sub h2z_ascii{
    my($string) = @_;

    $string = uc($string);
    $string =~ s/A/Ａ/g;
    $string =~ s/B/Ｂ/g;
    $string =~ s/C/Ｃ/g;
    $string =~ s/D/Ｄ/g;
    $string =~ s/E/Ｅ/g;
    $string =~ s/F/Ｆ/g;
    $string =~ s/G/Ｇ/g;
    $string =~ s/H/Ｈ/g;
    $string =~ s/I/Ｉ/g;
    $string =~ s/J/Ｊ/g;
    $string =~ s/K/Ｋ/g;
    $string =~ s/L/Ｌ/g;
    $string =~ s/M/Ｍ/g;
    $string =~ s/N/Ｎ/g;
    $string =~ s/O/Ｏ/g;
    $string =~ s/P/Ｐ/g;
    $string =~ s/Q/Ｑ/g;
    $string =~ s/R/Ｒ/g;
    $string =~ s/S/Ｓ/g;
    $string =~ s/T/Ｔ/g;
    $string =~ s/U/Ｕ/g;
    $string =~ s/V/Ｖ/g;
    $string =~ s/W/Ｗ/g;
    $string =~ s/X/Ｘ/g;
    $string =~ s/Y/Ｙ/g;
    $string =~ s/Z/Ｚ/g;
    $string =~ s/1/１/g;
    $string =~ s/2/２/g;
    $string =~ s/3/３/g;
    $string =~ s/4/４/g;
    $string =~ s/5/５/g;
    $string =~ s/6/６/g;
    $string =~ s/7/７/g;
    $string =~ s/8/８/g;
    $string =~ s/9/９/g;
    $string =~ s/0/０/g;
    $string =~ s/\+/＋/g;
    $string =~ s/\*/＊/g;
    $string =~ s/\#/＃/g;
    $string =~ s/\@/＠/g;

    return $string;
}

sub parse {
    my($query_str, $opt) = @_;

    ## 半角アスキー文字列を全角に置換
    $query_str = &h2z_ascii($query_str);

    my @phrases = ();
    ## フレーズを抽出("...")
    while($query_str =~ m/"([^"]+)"/g){
	my $phrase = $1;
	$phrase =~ s/[ |　]//g;

	push(@phrases, $phrase);
    }
    
    $query_str =~ s/"([^"]+)"//g;

    my @query_objs = ();
    my %wbuff = ();
    my %dbuff = ();
    foreach my $q (split(/[ |　]+/, $query_str)){
	my %words = ();
	my %dpnds = ();
	my $q_euc = encode('euc-jp', $q);
	my $q_obj;
	if($opt->{'dpnd'}){
	    my $knp_result_eucjp = `echo "$q_euc" | $TOOL_HOME/juman | $TOOL_HOME/knp -tab -dpnd -postprocess`;
	    my $temp = &Indexer::makeIndexfromKnpResult(decode('euc-jp', $knp_result_eucjp));
	    foreach my $k (keys %{$temp}){
		if(index($k, '->') > -1){
		    $dpnds{$k} = $temp->{$k};	
		    $dbuff{$k} = 0 unless(exists($dbuff{$k}));
		    $dbuff{$k} += $temp->{$k}->{score};
		}else{
		    $words{$k} = $temp->{$k};
		    $wbuff{$k} = 0 unless(exists($wbuff{$k}));
		    $wbuff{$k} += $temp->{$k}->{score};
		}
	    }

	    $q_obj = {words => \%words, dpnds => \%dpnds, ngrams => undef, windows => undef, rawstring => $q};

	    if($opt->{'window'}){
		my %windows = ();
		$temp = &Indexer::makeIndexArrayfromKnpResult(decode('euc-jp', $knp_result_eucjp));
		$temp = &Indexer::makeIndexfromIndexArray($temp, 15);
		foreach my $k (keys %{$temp}){
		    $windows{$k} += $temp->{$k};
		}
		$q_obj->{windows} = \%windows;
	    }
	}else{
	    my %words = ();
	    my $juman_result_eucjp = `echo "$q_euc" | $TOOL_HOME/juman`;
	    my $temp = &Indexer::makeIndexfromJumanResult(decode('euc-jp', $juman_result_eucjp));
	    foreach my $k (keys %{$temp}){
		$words{$k} = $temp->{$k};
		$wbuff{$k} = 0 unless(exists($wbuff{$k}));
		$wbuff{$k} += $temp->{$k}->{score};
	    }

	    $q_obj = {words => \%words, dpnds => undef, ngrams => undef, rawstring => $q};

	    if($opt->{'window'}){
		my %windows = ();
		$temp = &Indexer::makeIndexArrayfromJumanResult(decode('euc-jp', $juman_result_eucjp));
		$temp = &Indexer::makeIndexfromIndexArray($temp, 15);
		foreach my $k (keys %{$temp}){
		    $windows{$k} += $temp->{$k};
		}
		$q_obj->{windows} = \%windows;
	    }
	}
	push(@query_objs, $q_obj);
    }

    my %nbuff = ();
    # 文字トライグラムインデックスの作成
    foreach my $p (@phrases){
	my $n_grms = &Indexer::makeNgramIndex($p, 3);
	foreach my $k (keys %{$n_grms}){
	    $nbuff{$k} = 0 unless(exists($nbuff{$k}));
	    $nbuff{$k} += $n_grms->{$k}->{score};
	}
	my $q_obj = {words => undef, dpnds => undef, ngrams => $n_grms, rawstring => $p};
	push(@query_objs, $q_obj);
    }

#   debug_print(\@query_objs);

    return {query => \@query_objs, words => \%wbuff, dpnds => \%dbuff, ngrams => \%nbuff};
}

sub debug_print {
    my ($qs) = @_;
    foreach my $q (@{$qs}){
	my $str = encode('euc-jp', $q->{rawstring});
	print "q=$str\n";
	foreach my $k (sort {$q->{words}{$a}{pos} <=> $q->{words}{$b}{pos}} keys %{$q->{words}}){
	    my $k_euc = encode('euc-jp', $k);
	    printf("W %s %d\n", $k_euc, $q->{words}{$k}{pos});
	}

	foreach my $k (sort {$q->{dpnds}{$a}{pos} <=> $q->{dpnds}{$b}{pos}} keys %{$q->{dpnds}}){
	    my $k_euc = encode('euc-jp', $k);
	    printf("D %s %d\n", $k_euc, $q->{dpnds}{$k}{pos});
	}

	foreach my $k (sort {$q->{ngrams}{$a}{pos} <=> $q->{ngrams}{$b}{pos}} keys %{$q->{ngrams}}){
	    my $k_euc = encode('euc-jp', $k);
	    printf("P %s %d\n", $k_euc, $q->{ngrams}{$k}{pos});
	}
    }
	    
#    foreach my $e (sort {$m->{$a}->{pos} <=> $m->{$b}->{pos}} keys %{$m}){
#
#	my $e_euc = encode('euc-jp', $e);
#	printf("%s %d\n", $e_euc, $m->{$e}->{pos});
#    }
}


1;
