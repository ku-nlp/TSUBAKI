package Retrieve;

# $Id$

###################################################################
# 与えられた単語を含む文書IDをindex<NAME>.datから検索するモジュール
###################################################################

use strict;
use CDB_File;
use Encode;
use utf8;
use FileHandle;
use Storable;
use Error qw(:try);

my $DEBUG = 1;
my $host = `hostname`; chop($host);

# $DEBUG = 1 if($host eq "nlpc01\n");

sub new {
    my ($class, $dir, $type, $pos_skip) = @_;

    my $this = {IN => [], OFFSET => [], DOC_LENGTH => undef, TYPE => $type, INDEX_DIR => $dir, POS_SKIP => $pos_skip};

    my $fcnt = 0;
    # idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
    opendir(DIR, $dir) or die "$dir: $!\n";
    for my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next unless($d =~ /idx(\d+).$type.dat$/);
	my $NAME = $1;
	next if ($NAME > 50);

	## OFFSET(offset*.dat)を読み込み専用でtie
	my $offset_fp = "$dir/offset$NAME.$type.cdb";
	if(-e $offset_fp){
	    print STDERR "$host> loading offset database ($offset_fp)...\n" if($DEBUG);
	    tie %{$this->{OFFSET}[$fcnt]}, 'CDB_File', $offset_fp or die "$0: can't tie to $offset_fp $!\n";
	    print STDERR "$host> done.\n" if($DEBUG);
	}
	$fcnt++;
    }
    closedir(DIR);

    bless $this;
}

sub printLog{
    my($queries) = @_;
    my($sec, $min, $hour, $day, $mon, $year, @others) = localtime(time);
    my $date = sprintf("%d/%02d/%02d %02d:%02d:%02d", $year + 1900, $mon + 1,$day, $hour, $min, $sec);

    print STDERR "$host> now retrieving the following keyword(s) $date\n";
    my $q_str;
    foreach my $q (sort {$a->{id} <=> $b->{id}} @{$queries}){
	$q_str .= "$q->{keyword},";
    }
    chop($q_str);
    print STDERR "$host> ($q_str)\n";
}

sub search_wo_hash {
    my($this, $query_list, $dbuff, $registFlag, $no_position) = @_;

    ## 検索クエリが空なら空の結果を返す
    unless(defined($query_list)){
	my @results = ();
	push(@{$results[0]}, ());

	return \@results;
    }

    ## ログの表示
    &printLog($query_list);

    ## INDEXファイルの読み込み
    my $fcnt = 0;
    my $dir = $this->{INDEX_DIR};
    opendir(DIR, $dir);
    foreach my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next if $d !~ /idx(\d+).$this->{TYPE}.dat$/;
	my $id = $1;
	next if ($id > 50);

	# ファイル(idx*.dat)をオープンする
	$this->{IN}[$fcnt] = new FileHandle;
	open($this->{IN}[$fcnt], "< $dir/idx$id.$this->{TYPE}.dat") or die "$dir/idx$id.$this->{TYPE}.dat: $!\n";
	$fcnt++;
    }
    closedir(DIR);

    ## idxごとに検索
    my @doc_info;
    my @dumy = sort {$a->{gdf} <=> $b->{gdf}} @{$query_list};
    $query_list = \@dumy;
    my %did_buff = ();
    for (my $f_num = 0; $f_num < $fcnt; $f_num++) {
	for (my $i = 0; $i < scalar(@{$query_list}); $i++) {
	    my $query = $query_list->[$i]->{keyword};
	    my $qid = $query_list->[$i]->{id};
	    my $query_euc = encode('euc-jp',$query);

	    print STDERR "$host> idx_file(s)=$f_num, keyword(s)=$query(qid=$qid) $i\n" if($DEBUG);

	    unless(defined($this->{OFFSET}[$f_num]->{$query})){
		unless(defined($doc_info[$i])){
#		    my @tmp = ();
#		    $doc_info[$i] = \@tmp;
		    $doc_info[$i] = [];
		}
		print STDERR "$host> keyword=$query,ldf=0\n" if($DEBUG);
		next;
	    }

	    seek($this->{IN}[$f_num], $this->{OFFSET}[$f_num]->{$query}, 0);

	    my $char;
	    my @str;
	    my $buf;
	    while (read($this->{IN}[$f_num], $char, 1)) {
		if (unpack('c', $char) != 0) {
		    push(@str, $char);
		}
		else {
		    # 最初はキーワード（情報としては冗長）
		    $buf = join('', @str);
		    @str = ();

		    # 次にキーワードの文書頻度
		    read($this->{IN}[$f_num], $buf, 4);

		    my $ldf = unpack('L', $buf);
		    print STDERR "$host> keyword=$query,ldf=$ldf\n" if($DEBUG);
		    
		    # 文書IDと出現頻度(tf)の取得
		    for (my $j = 0; $j < $ldf; $j++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $did = unpack('L', $buf) + 0;
			
			read($this->{IN}[$f_num], $buf, 4);
			my $freq = unpack('L', $buf) + 0;
#			    syswrite STDERR, "$j ldf;$ldf did:$did freq:$freq\n" if (($j * 10) % $ldf == 0);
			
			if(defined($dbuff)){
			    if($registFlag > 0){
				$dbuff->{$did} = 1;
			    }else{
				unless(exists($dbuff->{$did})){
				    read($this->{IN}[$f_num], $buf, 4 * $freq);
				    next;
				}
			    }
			}
			
			my @pos = ();
			unless ($this->{POS_SKIP}) {
			    if ($no_position) {
				seek($this->{IN}[$f_num], $freq * 4, 1);
			    } else {
				for (my $k = 0; $k < $freq; $k++) {
				    read($this->{IN}[$f_num], $buf, 4);
				    my $p = unpack('L', $buf);
				    push(@pos, $p + 0);
				}
			    }
			}
			
			if ($no_position) {
			    push(@{$doc_info[$i]}, {did => $did, freq => $freq, qid => $qid});
			} else {
			    push(@{$doc_info[$i]}, {did => $did, freq => $freq, qid => $qid, pos => \@pos});
			}
		    }
		    last;
		}
	    }
	}
    }

    foreach my $r (@{$this->{IN}}){
	$r->close();
    }
    return \@doc_info;
}   

sub DESTROY {
    my ($this) = @_;

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	untie %{$this->{OFFSET}[$f_num]};
    }
}

1;
