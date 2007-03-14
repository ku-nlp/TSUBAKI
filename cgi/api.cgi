#!/home/skeiji/local/bin/perl

# REST API for search

# Request parameters
# query   : utf8 encoded query
# results : the number of search results
# start   : start position of search results

# Output response (XML)
# ResultSet : a set of results, this field has the following attributes
#   totalResultsAvailable : the number of all results
#   totalResultsReturned  : the number of returned results
#   firstResultPosition   : start position of search results
# Result    : a result

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use XML::Writer;
use XML::DOM;
use File::stat;
use POSIX qw(strftime);
use Encode qw(encode decode from_to);
use URI::Escape qw(uri_escape);
use IO::Socket;
use IO::Select;
use Time::HiRes;
use utf8;
use CDB_File;
use Data::Dumper;

use Indexer qw(makeIndexfromKnpResult makeIndexfromJumanResult);
use SearchEngine;
use QueryParser;
use SnippetMaker;

my @loadave = split(/ /, `uptime`);
chop($loadave[14]);
if($loadave[14] > 3.0){
    my $i = int(rand(10));
#   sleep(5 + $i);
}

my $cgi = new CGI;
my %params = ();
## 検索条件の初期化
$params{'ranking_method'} = 'OKAPI';
$params{'start'} = 0;
$params{'logical_operator'} = 'AND';
$params{'dpnd'} = 1;
$params{'results'} = 10;
$params{'dpnd_condition'} = 'OFF';
$params{'filter_simpages'} = 0;
$params{'only_hitcount'} = 0;

## 指定された検索条件に変更
$params{'URL'} = $cgi->param('URL') if($cgi->param('URL'));
$params{'query'} = decode('utf8', $cgi->param('query')) if($cgi->param('query'));
$params{'start'} = $cgi->param('start') if(defined($cgi->param('start')));
$params{'logical_operator'} = $cgi->param('logical') if(defined($cgi->param('logical')));
$params{'results'} = $cgi->param('results') if(defined($cgi->param('results')));
$params{'only_hitcount'} = $cgi->param('only_hitcount') if(defined($cgi->param('only_hitcount')));

if($cgi->param('dpnd') == 1){
    $params{'dpnd'} = 1;
}else{
    $params{'dpnd'} = 0;
}

if($cgi->param('filter_simpages') == 1){
    $params{'filter_simpages'} = 1;
}else{
    $params{'filter_simpages'} = 0;
}



my $date = `date +%m%d-%H%M%S`;
chomp ($date);
my $TOOL_HOME='/home/skeiji/local/bin';
my $INDEX_DIR = 'INDEX_NTCIR2';
my $PORT = 65000;
my $LOG_DIR = "/se_tmp";
my @HOSTS;
for(my $i = 161; $i < 192; $i++){
#    next if($i == 191);
    push(@HOSTS,   "157.1.128.$i");
}
my $CACHE_PROGRAM = 'http://tsubaki.ixnlp.nii.ac.jp/se/index.cgi';
my $HTML_PATH_TEMPLATE = "$INDEX_DIR/%02d/h%04d/%08d.html";
my $SF_PATH_TEMPLATE   = "$INDEX_DIR/%02d/x%04d/%08d.xml";



# current time
my $timestamp = strftime("%Y-%m-%d %T", localtime(time));

# # utf8 encoded query
# my $query = decode('utf8', $cgi->param('query'));
# my $INPUT = $query;
my $uri_escaped_query = uri_escape(encode('euc-jp', $params{'query'})); # uri_escape_utf8($query);

# # number of search results
# my $result_num = $cgi->param('results');
# $result_num = 10 unless $result_num; # default number of results

# my $RANKING_METHOD = $cgi->param('rank');
# $RANKING_METHOD = 'OKAPI'; # unless $RANKING_METHOD; # default number of results

# # start position of results
# my $start_num = $cgi->param('start');
# $start_num = 1 unless $start_num;
# my $START = $start_num;
# my $PRINT_THRESHOLD = $result_num + $start_num;

# get an operation
my $file_type = $cgi->param('format');

# my $LOGICAL_COND = $cgi->param('logical');
# $LOGICAL_COND = 'AND' unless $LOGICAL_COND; # default number of results

# my $ANALYZE_LEVEL = $cgi->param('analyze');
# $ANALYZE_LEVEL = 'JUMAN' unless($ANALYZE_LEVEL);

# my $VERBOSE = $cgi->param('verbose');
# $VERBOSE = 'ON' unless($VERBOSE);

# my $DEP_COND = $cgi->param('dep_cond');
# $DEP_COND = 'OFF' unless($DEP_COND);

# my $SIM_PAGES = $cgi->param('filter_simpages');
# $SIM_PAGES = 0 unless($SIM_PAGES);

# XML DOM Parser for acquiring information of HTML
my $parser = new XML::DOM::Parser;

if($file_type){
    my $fid = $cgi->param('id');

    if($fid eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "パラメータidの値が必要です。\n";
	exit(1);
    }

    $fid =~ /(\d\d)(\d\d)\d+/;
    my $dir_id = $1;
    my $subdir_id = "$1$2";
    my $dir_prefix = substr($file_type, 0, 1);

    unless($file_type eq "index"){
	print $cgi->header(-type => "text/$file_type", 
			   -charset => 'utf-8', 
			   );

	# my $filepath = "INDEX/$dir_prefix$subdir_id/$fid.$file_type";
	my $filepath = "$INDEX_DIR/$dir_id/$dir_prefix$subdir_id/$fid.$file_type";
	my $htmlfp = "$INDEX_DIR/$dir_id/h$subdir_id/$fid.html";
	my $content = '';
	if(-e $filepath){
	    $content = `/usr/local/bin/nkf --utf8 $filepath`;
	}else{
	    $filepath .= ".gz";
	    $content = `gunzip -c $filepath | /usr/local/bin/nkf --utf8`;
	}
	my $url = `head -1 ${htmlfp} | cut -f 2 -d ' '`;
	$content =~ s/Url=\"\"/Url=\"${url}\"/;
	print $content;
    }else{
	print $cgi->header(-type => "text/html", 
			   -charset => 'utf-8', 
			   );

	my $selecter = IO::Select->new;
	for(my $i = 0; $i < scalar(@HOSTS); $i++){
	    my $host = $HOSTS[$i];
	    my $socket = IO::Socket::INET->new(PeerAddr => $host,
					       PeerPort => $PORT,
					       Proto    => 'tcp',
					       );
	    $selecter->add($socket);
	    unless($socket){
		die "$host に接続できませんでした。 $!\n";
	    }
	    
	    # 文字列を送信
	    print $socket "GET,$fid\n";
	    $socket->flush();
	}

	# 文字列を受信
	my $buff = '';
	my $num_of_sockets = scalar(@HOSTS);
	while($num_of_sockets > 0){
	    my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	    foreach my $socket (@{$readable_sockets}){
		$buff = <$socket>;
		chomp($buff);
#		print "$buff\n";
#		from_to($buff, 'euc-jp', 'utf8');
#		$buff = `echo $buff | /usr/local/bin/nkf --utf8`;
		foreach (split(/,/,$buff)){
		    print "$_\n";
		}
		$selecter->remove($socket);
		$socket->close();
		$num_of_sockets--;
	    }
	}
    }
}else{
#    print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
#    print "ご迷惑をお掛けして申し訳ございませんが、APIサービスは現在停止しております。\n再開までしばらくお待ち下さい。\n";
#    exit(1);

    if($params{'query'} eq ''){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
	print "queryの値を指定して下さい。\n";
	exit(1);
    }

    my $start_time = Time::HiRes::time;
    my $query_utf8 = encode('utf8', $params{'query'});
    if($params{'only_hitcount'}){
	print $cgi->header(-type => 'text/plain', -charset => 'utf-8');
    }else{
	print $cgi->header(-type => 'text/xml',  -charset => 'utf-8');
    }

    # parse query
    my $query_objs = &QueryParser::parse($params{'query'}, \%params);

    ## 検索
    my $se_obj = new SearchEngine(\@HOSTS, $PORT, 'API');
    my($hitcount, $results) = $se_obj->search($query_objs->{query}, \%params);
    
    if($params{'only_hitcount'}){
	my $finish_time = Time::HiRes::time;
	my $search_time = $finish_time - $start_time;

	# ログの保存
	my $date = `date +%m%d-%H%M%S`; chomp ($date);
	open(OUT, ">> $LOG_DIR/input.log");
	my $param_str;
	foreach my $k (sort keys %params){
	    $param_str .= "$k=$params{$k},";
	}
	$param_str .= "hitcount=$hitcount,time=$search_time";
	print OUT "$date $ENV{REMOTE_ADDR} API $param_str\n";
	close(OUT);

	printf ("%d\n", $hitcount);
    }else{
	# 解析結果の表示
	## merging

	my $until = $params{'start'} + $params{'results'} - 1;
	$until = $hitcount if($hitcount < $until);
	$params{'results'} = $hitcount if($params{'results'} > $hitcount);

	my $max = 0;
	my @merged_results;
	while($until > scalar(@merged_results)){
	    for(my $k = 0; $k < scalar(@{$results}); $k++){
		next unless(defined($results->[$k]->[0]));
		
		if($results->[$max]->[0]->{score} <= $results->[$k]->[0]->{score}){
		    $max = $k;
		}
	    }
	    push(@merged_results, shift(@{$results->[$max]}));
	}
	
	my $finish_time = Time::HiRes::time;
	my $search_time = $finish_time - $start_time;

	# ログの保存
	my $date = `date +%m%d-%H%M%S`; chomp ($date);
	open(OUT, ">> $LOG_DIR/input.log");
	my $param_str;
	foreach my $k (sort keys %params){
	    $param_str .= "$k=$params{$k},";
	}
	$param_str .= "hitcount=$hitcount,time=$search_time";
	print OUT "$date $ENV{REMOTE_ADDR} API $param_str\n";
	close(OUT);
	
	my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);
	$writer->xmlDecl('utf-8');
	my @ret_result = &get_results_specified_num(\@merged_results, $params{'start'} - 1, $params{'results'}, $query_objs);
	$writer->startTag('ResultSet', time => $timestamp, query => $params{'query'}, 
			  totalResultsAvailable => scalar($hitcount), 
			  totalResultsReturned => scalar(@ret_result), 
			  firstResultPosition => $params{'start'},
			  logicalOperator => $params{'logical_operator'},
			  dpnd => $params{'dpnd'},
			  filterSimpages => $params{'filter_simpages'},
	    );
	
	for my $d (@ret_result) {
	    $writer->startTag('Result', Id => sprintf("%08d", $d->{did}), Score => sprintf("%.5f", $d->{score}));
	    
	    $writer->startTag('Title');
	    if(utf8::is_utf8($d->{title})){
		$d->{title} = encode('utf8', $d->{title});
	    }

	    $d->{title} =~ s/\x09//g;
	    $d->{title} =~ s/\x0a//g;
	    $d->{title} =~ s/\x0b//g;
	    $d->{title} =~ s/\x0c//g;
	    $d->{title} =~ s/\x0d//g;

	    $writer->characters($d->{title});
	    $writer->endTag('Title');
	    
	    $writer->startTag('Url');
	    $writer->characters($d->{original_url});
	    $writer->endTag('Url');

	    $writer->startTag('Snippet');
	    $writer->characters($d->{snippet});
	    $writer->endTag('Snippet');
	    
#	$writer->startTag('Charset');
#	$writer->characters($d->{charset});
#	$writer->endTag('Charset');
	    
#	$writer->startTag('TimeStamp');
#	$writer->characters($d->{timestamp});
#	$writer->endTag('TimeStamp');
	    
	    $writer->startTag('Cache');
	    $writer->startTag('Url');
	    $writer->characters(&get_cache_location($d->{did}, $uri_escaped_query));
	    $writer->endTag('Url');
	    $writer->startTag('Size');
	    $writer->characters(&get_cache_size($d->{did}));
	    $writer->endTag('Size');
	    $writer->endTag('Cache');
	    
	    $writer->endTag('Result');
	}
	
	$writer->endTag('ResultSet');
	$writer->end();
    }
}

sub parseQuery{
    my($string) = @_;

    my $rawstring;
    my %trigram = ();
    my @rawtrigrams = ();
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

    while($string =~ m/"([^"]+)"/g){
	my $head = "$`";
	my $tail = "$'";
	my $trigram_kwd = $1;

	$rawstring .= ("$head $tail");
	$trigram_kwd =~ s/[ |　]//g;
	push(@rawtrigrams, $trigram_kwd);
	my $temp = &Indexer::makeNgramIndex($trigram_kwd, 3);
	foreach my $k (keys %{$temp}){
	    $trigram{$k} = $temp->{$k};
	}
    }
    $rawstring = $string unless($string =~ /"([^"]+)"/);
    my @rawstrings = split(/[ |　]/, $rawstring);

    return (\%trigram, \@rawstrings, \@rawtrigrams);
}

sub get_results_specified_num {
    my ($result, $start, $num, $query_objs) = @_;
    my (@ret);

    my %urldbs = ();
    my $dbfp = "/home/skeiji/title.cdb";
    tie my %titledb, 'CDB_File', $dbfp or die "$0: can't tie to $dbfp $!\n";
#    $start--; # index starts from 0
    my $prev_page = undef;
    for my $i ($start .. $start + $num - 1) {
	last if $i >= scalar(@$result);

	my $id = $result->[$i]->{did};
	my $url;
	my $idtmp = sprintf("%08d", $id);
	$idtmp =~ /(\d\d)\d\d\d\d\d\d$/;
	if(exists($urldbs{$1})){
	    $url = $urldbs{$1}->{$idtmp};
	}else{
	    my $urldbfp = "/var/www/cgi-bin/dbs/$1.url.cdb";
	    tie my %urldb, 'CDB_File', "$urldbfp" or die "$0: can't tie to $urldbfp $!\n";
	    $urldbs{$1} = \%urldb;
	    $url = $urldb{$idtmp};
	}

 	my $title;
	$title = decode('euc-jp', $titledb{$idtmp}) if(exists($titledb{$idtmp}));

	$result->[$i]->{title} = $title;
	$result->[$i]->{original_url} = $url;
#	$result->[$i]->{charset} = $charset;
#	$result->[$i]->{timestamp} = $time;

	my $xmlpath = sprintf("$INDEX_DIR/%02d/x%04d/%08d.xml", $id / 1000000, $id / 10000, $id);
	## snippet用に重要文を抽出
	my $sent_objs = &SnippetMaker::extractSentence($query_objs, $xmlpath);

	my $snippet = '';
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

		$snippet .= $surf;
		$length += length($surf);
		if($length > 200){
		    $snippet .= " ...";
		    last;
		}
	    }
	    last if($length > 200);
	}

	my $score = $result->[$i]->{score};
	if($prev_page->{title} eq $title &&
	   $prev_page->{score} == $score){
	    if($params{'filter_simpages'}){
		next;
	    }
	}else{
	    my $sim = 0;
	    if(defined($prev_page->{words})){
		$sim = &calculateSimilarity($prev_page->{words}, \%words);
	    }
	    
	    $prev_page->{words} = \%words;
	    $prev_page->{title} = $title;
	    $prev_page->{score} = $score;
	    
	    if($params{'filter_simpages'} && $sim > 0.9){
		next;
	    }
	}
	
	$result->[$i]->{snippet} = encode('utf8', $snippet);
	$result->[$i]->{snippet} = encode('utf8', $snippet) if(utf8::is_utf8($snippet));
	push(@ret, $result->[$i]);
    }
    
    foreach my $k (keys %urldbs){
	untie %{$urldbs{$k}};
    }
    untie %titledb;
    return @ret;
}

sub norm {
    my ($v) = @_;
    my $norm = 0;
    foreach my $k (keys %{$v}){
	$norm += ($v->{$k}**2);
    }
    return sqrt($norm);
}

sub calculateSimilarity {
    my ($v1, $v2) = @_;
    my $size1 = scalar(keys %{$v1});
    my $size2 = scalar(keys %{$v2});
    if($size1 > $size2){
	return calculateSimilarity($v2, $v1);
    }

    my $sim = 0;
    foreach my $k (keys %{$v1}){
	next unless(exists($v2->{$k}));
	$sim += ($v1->{$k} * $v2->{$k});
    }

    my $bunbo = &norm($v1) * &norm($v2);
    if($bunbo == 0){
	return 0;
    }else{
	return ($sim / $bunbo);
    }
#   return $sim;
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

sub extractSentence {
    my($query, $xmlpath) = @_;

    my @sent_objs = ();
    if(-e $xmlpath){
	open(READER, $xmlpath);
    }else{
	$xmlpath .= ".gz";
	open(READER,"zcat $xmlpath |");
    }

    my $buff;
    while(<READER>){
	$buff .= $_;
	if($_ =~ m!</Annotation>!){
	    $buff = decode('utf8', $buff);
	    if($buff =~ m/<Annotation Scheme=\"Knp\"><!\[CDATA\[((?:.|\n)+?)\]\]><\/Annotation>/){
		my %temp1 = ();
		my @temp2 = ();
		my $knpresult = $1;
		my $sent_obj = {rawstring => undef,
				words => \%temp1,
				list => \@temp2,
				score => 0.0
		};
		
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
		    if($line =~ /\<意味有\>/){
			next if ($line =~ /\<記号\>/); ## <意味有>タグがついてても<記号>タグがついていれば削除
			
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
		    }

		    push(@{$sent_obj->{list}}, $mrph_obj);
		}
			    
		my $score = 0;
		foreach my $k (keys %{$query->{words}}){
		    $score += $sent_obj->{words}->{$k} if(exists($sent_obj->{words}->{$k}));
		}

		foreach my $k (keys %{$query->{ngrams}}){
		    $score += 1 if($sent_obj->{rawstring} =~ /$k/);
		}

		if($score > 0){
#		    $sent_obj->{score} = ($score * length($sent_obj->{rawstring}));
		    $sent_obj->{score} = ($score * log(length($sent_obj->{rawstring})));
		    push(@sent_objs, $sent_obj);
		}
	    }
	    $buff = '';
	}
    }
    close(READER);
 
    return \@sent_objs;
}


sub get_cache_location {
    my ($id, $query) = @_;

    my $loc = sprintf($HTML_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id);
#    return "${CACHE_PROGRAM}?loc=$loc&query=$uri_escaped_query";
    return "${CACHE_PROGRAM}?URL=$loc&KEYS=$uri_escaped_query";
}

sub get_cache_size {
    my ($id) = @_;

    my $st = stat(sprintf($HTML_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id) . ".gz");
    return '' unless $st;
    return $st->size;
}

sub get_file_info {
    my ($id) = @_;

    my $filename = sprintf($SF_PATH_TEMPLATE, $id / 1000000, $id / 10000, $id);
    return '' unless -f $filename;
    my $doc = $parser->parsefile($filename);

    my $sentences = $doc->getElementsByTagName('S');
    for my $i (0 .. $sentences->getLength - 1) { # for each S
	my $sentence = $sentences->item($i);
	for my $s_child_node ($sentence->getChildNodes) {
	    if ($s_child_node->getNodeName eq 'RawString') { # one of the children of S is RawString
		for my $node ($s_child_node->getChildNodes) {
		    $doc->dispose;
		    return $node->getNodeValue; # the first one is title
		}
	    }
	}
    }

    $doc->dispose;
    return '';
}

# sub broadcastSearch{
#     my($trigram_qs, $search_qs) = @_;
#     my $trigram_qs_str = join(':',(keys %{$trigram_qs}));
#     my $search_qs_str  = join(':',(keys %{$search_qs}));
#     $trigram_qs_str = 'null' if($trigram_qs_str eq '');

#     my $selecter = IO::Select->new;
#     for(my $i = 0; $i < scalar(@HOSTS); $i++){
# 	my $host = $HOSTS[$i];
# 	my $socket = IO::Socket::INET->new(PeerAddr => $host,
# 					   PeerPort => $PORT,
# 					   Proto    => 'tcp',
# 					   );
# 	$selecter->add($socket);
# 	unless($socket){
# 	    die "$host に接続できませんでした。 $!\n";
# 	}

# 	# 文字列を送信
# 	my $str_search_q = join(":",keys %{$search_qs});
# 	my $topN = $START + $PRINT_THRESHOLD;
# 	print $socket "SEARCH,$trigram_qs_str $search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$ANALYZE_LEVEL,$DEP_COND,$topN\n";
# #	print $socket "SEARCH,$trigram_qs_str $search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$ANALYZE_LEVEL\n";
# 	$socket->flush();
#     }
    
#     # 文字列を受信
#     my @results;
#     my $hitcount = 0;
#     my $num_of_sockets = scalar(@HOSTS);
#     while($num_of_sockets > 0){
# 	my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
# 	foreach my $socket (@{$readable_sockets}){
# 	    my $buff = <$socket>;
# 	    chop($buff);
# 	    $hitcount += $buff;

# 	    $buff = <$socket>;
# 	    $buff =~ s/\[RET\]/\n/g;
# 	    push(@results, &decodeResult($buff));
		
# 	    $selecter->remove($socket);
# 	    $socket->close();
# 	    $num_of_sockets--;
# 	}
#     }
#     push(@results,$hitcount);
#     return \@results;
# }

# sub broadcastSearch2{
#     my($hosts,$port,$level,$dep_cond,$verbose,$qs) = @_;
#     my $selecter = IO::Select->new;
#     my $search_qs_str = join(":",(keys %{$qs}));
# #    print "<!-- keys " . encode('utf8',$search_qs_str) . " -->\n";
# #    print "<!-- port " . $port . " -->\n";
# #    print "<!-- level " .$level . " -->\n";

#     for(my $i = 0; $i < scalar(@{$hosts}); $i++){
# 	my $host = $hosts->[$i];
# 	my $socket = IO::Socket::INET->new(PeerAddr => $host,
# 					   PeerPort => $port,
# 					   Proto    => 'tcp',
# 					   );
# 	$selecter->add($socket);
# 	unless($socket){
# 	    die "$host に接続できませんでした。 $!\n";
# 	}
	    
# 	# 文字列を送信
# 	print $socket "SEARCH,$search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$level,$dep_cond,$PRINT_THRESHOLD\n";
# #	print "<!-- SEARCH,$search_qs_str,$RANKING_METHOD,$LOGICAL_COND,$level -->\n";
# 	$socket->flush();
#     }
    
#     # 文字列を受信
#     my @results;
#     my $hitcount = 0;
#     my $num_of_sockets = scalar(@{$hosts});
#     while($num_of_sockets > 0){
# 	my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
# 	foreach my $socket (@{$readable_sockets}){
# 	    my $buff = <$socket>;
# 	    chop($buff);
# 	    $hitcount += $buff;
# #	    print "<!-- $hitcount -->\n";

# 	    $buff = <$socket>;
# 	    $buff =~ s/\[RET\]/\n/g;
# 	    push(@results, &decodeResult($buff));
		
# 	    $selecter->remove($socket);
# 	    $socket->close();
# 	    $num_of_sockets--;
# 	}
#     }
#     push(@results,$hitcount);
#     return \@results;
# }

sub decodeResult{
    my($result_str) = @_;
    my @result_ary;
    foreach (split(/\n/, $result_str)){
	my($did,$score) = split(/,/, $_);
	push(@result_ary, {"did" => $did, "score" => $score});
    }
    return \@result_ary;
}
