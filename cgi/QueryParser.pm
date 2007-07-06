package QueryParser;

# 検索クエリを内部形式に変換するモジュール
# my $TOOL_HOME='/home/skeiji/local/bin';

use strict;
use Encode;
use utf8;
use Unicode::Japanese;
use KNP;
use Indexer;
use SynGraph;
use QueryKeyword;

sub new {
    my ($class, $opts) = @_;
    my $this = {
	INDEXER => new Indexer(),
	KNP => new KNP(-Command => "$opts->{KNP_PATH}/knp",
		       -Option => join(' ', @{$opts->{KNP_OPTIONS}}),
		       -JumanCommand => "$opts->{JUMAN_PATH}/juman"),
	SYNGRAPH => new SynGraph($opts->{SYNDB_PATH})
    };

    bless $this;
}

sub parse {
    my ($this, $qks_str, $opt) = @_;

    ## 空白で区切る
    my @qks = ();
    my %wbuff = ();
    my %dbuff = ();

    foreach my $q_str (split(/(?: |　)+/, $qks_str)) {
	my $near = -1;
	## フレーズ検索かどうかの判定
	if ($q_str =~ /^"(.+)?"$/){
	    $near = 1;
	    $q_str = $1;
	}

	## 近接検索かどうかの判定
	if ($q_str =~ /^(.+)?~(\d+)$/){
	    $q_str = $1;
	    $near = $2;
	}

	## 半角アスキー文字列を全角に置換する
	$q_str = Unicode::Japanese->new($q_str)->h2z->getu;
	my $q;
	if ($opt->{syngraph}) {
	    $q= new QueryKeyword($q_str, $near, $opt->{logical_cond_qkw}, {knp => $this->{KNP}, indexer => $this->{INDEXER}, syngraph => $this->{SYNGRAPH}});
	} else {
	    $q= new QueryKeyword($q_str, $near, $opt->{logical_cond_qkw}, {knp => $this->{KNP}, indexer => $this->{INDEXER}});
	}	    

	push(@qks, $q);
    }

    my $qid = 0;
    my %qid2rep = ();
    foreach my $qk (@qks) {
	foreach my $reps (@{$qk->{words}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{qid} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid++;
	    }
	}

	foreach my $reps (@{$qk->{dpnds}}) {
	    foreach my $rep (@{$reps}) {
		$rep->{qid} = $qid;
		$qid2rep{$qid} = $rep->{string};
		$qid++;
	    }
	}
    }
	
    return {keywords => \@qks, logical_cond_qk => $opt->{logical_cond_qk}, only_hitcount => $opt->{only_hitcount}, qid2rep => \%qid2rep};
}

sub DESTROY {
    my ($this) = @_;
#     foreach my $cdb (@{$this->{DF_WORD_DBs}}) {
# 	untie %{$cdb};
#     }
#     foreach my $cdb (@{$this->{DF_DPND_DBs}}) {
# 	untie %{$cdb};
#     }
}

# sub parse_with_syngraph {
#     my($query_str, $opt) = @_;
#     my $stop_hypernym_fp = '/home/skeiji/stop_hypernyms';
#     my @stops = ();
#     open(READER, "$stop_hypernym_fp");
#     while(<READER>){
# 	my($freq, $word) = split(/ /,$_);
# 	my($kanji, $yomi) = split(/\//, $word);
# 	push(@stops, decode('euc-jp', $kanji));
#     }
#     close(READER);

#     my $DFDB_DIR = '/var/www/cgi-bin/cdbs-syn';
#     my @$this->{DF_WORD_DBs} = ();
#     my @DF_DPND_DBs = ();
#     opendir(DIR, $DFDB_DIR);
#     foreach my $cdbf (readdir(DIR)) {
# 	next unless ($cdbf =~ /cdb/);
	
# 	my $fp = "$DFDB_DIR/$cdbf";
# 	tie my %dfdb, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
# 	if (index($cdbf, 'dpnd') > 0) {
# 	    push(@DF_DPND_DBs, \%dfdb);
# 	} elsif (index($cdbf, 'word') > 0) {
# 	    push(@$this->{DF_WORD_DBs}, \%dfdb);
# 	}
#     }
#     closedir(DIR);

#     ## 空白で区切る
#     my @queries = split(/(?: |　)+/, $query_str);
#     my @query_objs = ();
#     my %wbuff = ();
#     my %dbuff = ();
#     my $indexer = new Indexer();
#     my $knp = new KNP(-Command => "$TOOL_HOME/knp",
# 		      -Option => '-tab -dpnd -postprocess',
# 		      -JumanCommand => "$TOOL_HOME/juman");
#     my $syn = new SynGraph($syndbdir);

#     my $regnode_option;
#     $regnode_option->{relation} = 1;
#     $regnode_option->{antonym} = 1;

#     my $sid = 0;
#     my $phrasal_flag = 0;
#     my $near_flag = 0;
#     foreach my $q (@queries){
# 	my $near = -1;
# 	## フレーズ検索かどうかの判定
# 	if($q =~ /^"(.+)?"$/){
# 	    $near = 1;
# 	    $q = $1;
# 	    $phrasal_flag = 1;
# 	}

# 	## 近接検索かどうかの判定
# 	if($q =~ /^(.+)?~(\d+)$/){
# 	    $q = $1;
# 	    $near_flag = 1;
# 	}

# 	## 半角アスキー文字列を全角に置換する
# 	$q = &h2z_alpha($q);

# 	my %buff = ();

# 	my $knp_result = $knp->parse($q);
# 	$knp_result->set_id($sid++);
# 	my $syn_result = $syn->OutputSynFormat($knp_result, $regnode_option);
# 	my $s_all = $syn_result;
# 	$s_all =~ s/>/&gt;/g;
# 	$s_all =~ s/</&lt;/g;
# 	$s_all =~ s/\n/<br>\n/g;
# #	print $s_all;
# #	print "<hr>\n";

# 	my $indice = $indexer->makeIndexfromSynGraph($syn_result);
# 	foreach my $k (keys %{$indice}){
# 	    next unless ($k =~ /^s\d+/);

# 	    if(index($k, '<上位語>') > 0){
# 		my $stop_flag = 0;
# 		foreach my $stopwd (@stops){
# 		    if(index($k, "$stopwd<上位語>") > 0){
# 			$stop_flag = 1;
# 			last;
# 		    }
# 		}
# 		next if($stop_flag > 0);
# 	    }

# 	    $buff{$indice->{$k}->{group_id}} = () unless(exists($buff{$indice->{$k}->{group_id}}));
# 	    push(@{$buff{$indice->{$k}->{group_id}}}, $indice->{$k});

# 	    if(index($k, '->') > 0){
# 		my ($r, $l) = split('->', $k);
# 		next unless ($r =~ /^s\d+/);
# 		next unless ($l =~ /^s\d+/);

# 		$dbuff{$k} = 0 unless(exists($dbuff{$k}));
# 		$dbuff{$k} += $indice->{$k}{freq};
# 	    }else{
# 		$wbuff{$k} = 0 unless(exists($wbuff{$k}));
# 		$wbuff{$k} += $indice->{$k}{freq};
# 	    }
# 	}
	
# 	my @words = ();
# 	my @dpnds = ();
# 	foreach my $group_id (sort {$buff{$a}->[0]->{pos} <=> $buff{$b}->[0]->{pos}} keys %buff){
# 	    my @reps_word;
# 	    my @reps_dpnd;
# 	    foreach my $m (@{$buff{$group_id}}){
# 		my $k = $m->{rawstring};
# 		my $k_utf8 = encode('utf8', $m->{rawstring});
# 		my $gdf = 0;
# 		if(index($k, '->') > 0){
# 		    foreach my $dfdb (@DF_DPND_DBs) {
# 			if (exists($dfdb->{$k_utf8})) {
# 			    $gdf = $dfdb->{$k_utf8};
# 			    last;
# 			}
# 		    }
# 		    $m->{gdf} = $gdf;

# 		    push(@reps_dpnd, $m);
# 		}else{
# 		    foreach my $dfdb (@$this->{DF_WORD_DBs}) {
# 			if (exists($dfdb->{$k_utf8})) {
# 			    $gdf = $dfdb->{$k_utf8};
# 			    last;
# 			}
# 		    }
# 		    $m->{gdf} = $gdf;

# 		    push(@reps_word, $m);
# 		}
# 	    }
# 	    push (@words, \@reps_word) if(scalar(@reps_word) > 0);
# 	    push (@dpnds, \@reps_dpnd) if(scalar(@reps_dpnd) > 0);
# 	}
	
# 	foreach my $m (@words){
# 	    foreach my $w (@{$m}){
# #		print $w->{rawstring} . "&nbsp;";
# 	    }
# #	    print "<br>\n";
# 	}
# #	print "$near <hr>\n";

# 	push(@query_objs, {words => \@words, dpnds => \@dpnds, near => $near, rawstring => $q});
#     }

#     ###########################################################
#     # 単語、係り受けそれぞれの文書頻度データベースをuntieする #
#     ###########################################################
#     foreach my $cdb (@$this->{DF_WORD_DBs}) {
# 	untie %{$cdb};
#     }
#     foreach my $cdb (@DF_DPND_DBs) {
# 	untie %{$cdb};
#     }

#     return {query => \@query_objs, words => \%wbuff, dpnds => \%dbuff, contains_phrasal_query => $phrasal_flag, contains_near_operator => $near_flag};
# }

# sub h2z_alpha{
#     my($text) = @_;

#     my @cbuff = ();
#     my @ch_codes = unpack("U0U*", encode('utf8', $text));
#     for(my $i = 0; $i < scalar(@ch_codes); $i++){
# 	my $ch_code = $ch_codes[$i];
# 	if(0x0020 < $ch_code && $ch_code < 0x007f){
# 	    $ch_code += 0xfee0;
# 	    push(@cbuff, $ch_code);
# 	}else{
# 	    push(@cbuff, $ch_code);
# 	}
#     }
#     my $tmp = pack("U0U*",@cbuff);
#     return $tmp;
# }

1;
