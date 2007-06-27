package QueryParser;

# 検索クエリを内部形式に変換するモジュール
my $TOOL_HOME='/home/skeiji/local/bin';

use strict;
use Encode;
use utf8;
use KNP;
use Indexer;
use SynGraph;

# use lib qw(/home/skeiji/local/lib/perl5/site_perl/5.8.8);

my $syndbdir = '/home/skeiji/SynGraph/syndb/i686';

our @EXPORT = qw(parse, parse_with_syngraph);

sub h2z_alpha{
    my($text) = @_;

    my @cbuff = ();
    my @ch_codes = unpack("U0U*", encode('utf8', $text));
    for(my $i = 0; $i < scalar(@ch_codes); $i++){
	my $ch_code = $ch_codes[$i];
	if(0x0020 < $ch_code && $ch_code < 0x007f){
	    $ch_code += 0xfee0;
	    push(@cbuff, $ch_code);
	}else{
	    push(@cbuff, $ch_code);
	}
    }
    my $tmp = pack("U0U*",@cbuff);
    return $tmp;
}

sub parse {
    my($query_str, $opt) = @_;

    my $DFDB_DIR = '/var/www/cgi-bin/cdbs-knp';
    my @DF_WORD_DBs = ();
    my @DF_DPND_DBs = ();
    opendir(DIR, $DFDB_DIR);
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	
	my $fp = "$DFDB_DIR/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	if (index($cdbf, 'dpnd') > 0) {
	    push(@DF_DPND_DBs, \%dfdb);
	} elsif (index($cdbf, 'word') > 0) {
	    push(@DF_WORD_DBs, \%dfdb);
	}
    }
    closedir(DIR);

    ## 空白で区切る
    my @queries = split(/(?: |　)+/, $query_str);
    my @query_objs = ();
    my %wbuff = ();
    my %dbuff = ();
    my $indexer = new Indexer();
    my $knp = new KNP(-Command => "$TOOL_HOME/knp",
		      -Option => '-tab -dpnd -postprocess',
		      -JumanCommand => "$TOOL_HOME/juman");
    foreach my $q (@queries){
	my $near = -1;
	## フレーズ検索かどうかの判定
	if($q =~ /^"(.+)?"$/){
	    $near = 1;
	    $q = $1;
	}

	## 近接検索かどうかの判定
	if($q =~ /^(.+)?~(\d+)$/){
	    $q = $1;
#	    $opt->{'near'} = $2 + 1;
	    $near = $2 + 1;
	}

	## 半角アスキー文字列を全角に置換する
	$q = &h2z_alpha($q);

	my %buff = ();
	my $temp = $indexer->makeIndexfromKnpResult($knp->parse($q)->all);
	foreach my $k (keys %{$temp}){
	    $buff{$temp->{$k}->{group_id}} = () unless(exists($buff{$temp->{$k}->{group_id}}));
	    push(@{$buff{$temp->{$k}->{group_id}}}, $temp->{$k});

	    if(index($k, '->') > 0){
		$dbuff{$k} = 0 unless(exists($dbuff{$k}));
		$dbuff{$k} += $temp->{$k}{freq};
	    }else{
		$wbuff{$k} = 0 unless(exists($wbuff{$k}));
		$wbuff{$k} += $temp->{$k}{freq};
	    }
	}
	
	my @words = ();
	my @dpnds = ();
	foreach my $gid (sort {$buff{$a}->[0]->{pos} <=> $buff{$b}->[0]->{pos}} keys %buff){
	    my @reps_word;
	    my @reps_dpnd;
	    foreach my $m (@{$buff{$gid}}){
		my $k = $m->{rawstring};
		my $k_utf8 = encode('utf8', $m->{rawstring});
		my $gdf = 0;
		if(index($k, '->') > 0){
		    foreach my $dfdb (@DF_DPND_DBs) {
			if (exists($dfdb->{$k_utf8})) {
			    $gdf = $dfdb->{$k_utf8};
			    last;
			}
		    }
		    $m->{gdf} = $gdf;

		    push(@reps_dpnd, $m);
		}else{
		    foreach my $dfdb (@DF_WORD_DBs) {
			if (exists($dfdb->{$k_utf8})) {
			    $gdf = $dfdb->{$k_utf8};
			    last;
			}
		    }
		    $m->{gdf} = $gdf;

		    push(@reps_word, $m);
		}
	    }
	    push (@words, \@reps_word) if(scalar(@reps_word) > 0);
	    push (@dpnds, \@reps_dpnd) if(scalar(@reps_dpnd) > 0);
	}
	
# 	foreach my $m (@words){
# 	    foreach my $w (@{$m}){
# 		print $w->{rawstring} . "&nbsp;";
# 	    }
# 	    print "<br>\n";
# 	}
#	print "$near <hr>\n";

	push(@query_objs, {words => \@words, dpnds => \@dpnds, near => $near, rawstring => $q});
    }

    ###########################################################
    # 単語、係り受けそれぞれの文書頻度データベースをuntieする #
    ###########################################################
    foreach my $cdb (@DF_WORD_DBs) {
	untie %{$cdb};
    }
    foreach my $cdb (@DF_DPND_DBs) {
	untie %{$cdb};
    }

    return {query => \@query_objs, words => \%wbuff, dpnds => \%dbuff};
}

sub parse_with_syngraph {
    my($query_str, $opt) = @_;
    my $stop_hypernym_fp = '/home/skeiji/stop_hypernyms';
    my @stops = ();
    open(READER, "$stop_hypernym_fp");
    while(<READER>){
	my($freq, $word) = split(/ /,$_);
	my($kanji, $yomi) = split(/\//, $word);
	push(@stops, decode('euc-jp', $kanji));
    }
    close(READER);

    my $DFDB_DIR = '/var/www/cgi-bin/cdbs-syn';
    my @DF_WORD_DBs = ();
    my @DF_DPND_DBs = ();
    opendir(DIR, $DFDB_DIR);
    foreach my $cdbf (readdir(DIR)) {
	next unless ($cdbf =~ /cdb/);
	
	my $fp = "$DFDB_DIR/$cdbf";
	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	if (index($cdbf, 'dpnd') > 0) {
	    push(@DF_DPND_DBs, \%dfdb);
	} elsif (index($cdbf, 'word') > 0) {
	    push(@DF_WORD_DBs, \%dfdb);
	}
    }
    closedir(DIR);

    ## 空白で区切る
    my @queries = split(/(?: |　)+/, $query_str);
    my @query_objs = ();
    my %wbuff = ();
    my %dbuff = ();
    my $indexer = new Indexer();
    my $knp = new KNP(-Command => "$TOOL_HOME/knp",
		      -Option => '-tab -dpnd -postprocess',
		      -JumanCommand => "$TOOL_HOME/juman");
    my $syn = new SynGraph($syndbdir);

    my $regnode_option;
    $regnode_option->{relation} = 1;
    $regnode_option->{antonym} = 1;

    my $sid = 0;
    my $phrasal_flag = 0;
    my $near_flag = 0;
    foreach my $q (@queries){
	my $near = -1;
	## フレーズ検索かどうかの判定
	if($q =~ /^"(.+)?"$/){
	    $near = 1;
	    $q = $1;
	    $phrasal_flag = 1;
	}

	## 近接検索かどうかの判定
	if($q =~ /^(.+)?~(\d+)$/){
	    $q = $1;
	    $near_flag = 1;
	}

	## 半角アスキー文字列を全角に置換する
	$q = &h2z_alpha($q);

	my %buff = ();

	my $knp_result = $knp->parse($q);
	$knp_result->set_id($sid++);
	my $syn_result = $syn->OutputSynFormat($knp_result, $regnode_option);
	my $s_all = $syn_result;
	$s_all =~ s/>/&gt;/g;
	$s_all =~ s/</&lt;/g;
	$s_all =~ s/\n/<br>\n/g;
#	print $s_all;
#	print "<hr>\n";

	my $temp = $indexer->makeIndexfromSynGraph($syn_result);
	foreach my $k (keys %{$temp}){
	    next unless ($k =~ /^s\d+/);

	    if(index($k, '<上位語>') > 0){
		my $stop_flag = 0;
		foreach my $stopwd (@stops){
		    if(index($k, "$stopwd<上位語>") > 0){
			$stop_flag = 1;
			last;
		    }
		}
		next if($stop_flag > 0);
	    }

	    $buff{$temp->{$k}->{group_id}} = () unless(exists($buff{$temp->{$k}->{group_id}}));
	    push(@{$buff{$temp->{$k}->{group_id}}}, $temp->{$k});

	    if(index($k, '->') > 0){
		my ($r, $l) = split('->', $k);
		next unless ($r =~ /^s\d+/);
		next unless ($l =~ /^s\d+/);

		$dbuff{$k} = 0 unless(exists($dbuff{$k}));
		$dbuff{$k} += $temp->{$k}{freq};
	    }else{
		$wbuff{$k} = 0 unless(exists($wbuff{$k}));
		$wbuff{$k} += $temp->{$k}{freq};
	    }
	}
	
	my @words = ();
	my @dpnds = ();
	foreach my $gid (sort {$buff{$a}->[0]->{pos} <=> $buff{$b}->[0]->{pos}} keys %buff){
	    my @reps_word;
	    my @reps_dpnd;
	    foreach my $m (@{$buff{$gid}}){
		my $k = $m->{rawstring};
		my $k_utf8 = encode('utf8', $m->{rawstring});
		my $gdf = 0;
		if(index($k, '->') > 0){
		    foreach my $dfdb (@DF_DPND_DBs) {
			if (exists($dfdb->{$k_utf8})) {
			    $gdf = $dfdb->{$k_utf8};
			    last;
			}
		    }
		    $m->{gdf} = $gdf;

		    push(@reps_dpnd, $m);
		}else{
		    foreach my $dfdb (@DF_WORD_DBs) {
			if (exists($dfdb->{$k_utf8})) {
			    $gdf = $dfdb->{$k_utf8};
			    last;
			}
		    }
		    $m->{gdf} = $gdf;

		    push(@reps_word, $m);
		}
	    }
	    push (@words, \@reps_word) if(scalar(@reps_word) > 0);
	    push (@dpnds, \@reps_dpnd) if(scalar(@reps_dpnd) > 0);
	}
	
	foreach my $m (@words){
	    foreach my $w (@{$m}){
#		print $w->{rawstring} . "&nbsp;";
	    }
#	    print "<br>\n";
	}
#	print "$near <hr>\n";

	push(@query_objs, {words => \@words, dpnds => \@dpnds, near => $near, rawstring => $q});
    }

    ###########################################################
    # 単語、係り受けそれぞれの文書頻度データベースをuntieする #
    ###########################################################
    foreach my $cdb (@DF_WORD_DBs) {
	untie %{$cdb};
    }
    foreach my $cdb (@DF_DPND_DBs) {
	untie %{$cdb};
    }

    return {query => \@query_objs, words => \%wbuff, dpnds => \%dbuff, contains_phrasal_query => $phrasal_flag, contains_near_operator => $near_flag};
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
