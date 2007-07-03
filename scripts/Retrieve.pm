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
use Devel::Size qw/size total_size/;
use Devel::Size::Report qw/report_size/;

my $DEBUG = 1;
my $host = `hostname`; chop($host);

# $DEBUG = 1 if($host eq "nlpc01\n");

sub new {
    my ($class, $dir, $type, $skippos, $verbose) = @_;

    my $this = {
	IN => [],
	OFFSET => [],
	DOC_LENGTH => undef,
	TYPE => $type,
	INDEX_DIR => $dir,
	SKIPPOS => $skippos,
	VERBOSE => $verbose
    };

    my $fcnt = 0;
    # idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
    opendir(DIR, $dir) or die "$dir: $!\n";
    for my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next unless($d =~ /idx(\d+).$type.dat$/);
	my $NAME = $1;

	## OFFSET(offset*.dat)を読み込み専用でtie
	my $offset_fp = "$dir/offset$NAME.$type.cdb";
	if(-e $offset_fp){
	    print STDERR "$host> loading offset database ($offset_fp)...\n" if ($this->{VERBOSE});
	    tie %{$this->{OFFSET}[$fcnt]}, 'CDB_File', $offset_fp or die "$0: can't tie to $offset_fp $!\n";
	    print STDERR "$host> done.\n" if ($this->{VERBOSE});
	}
	$fcnt++;
    }
    closedir(DIR);

    bless $this;
}

sub printLog {
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

sub search {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $no_position) = @_;

    ## INDEXファイルの読み込み
    my $fcnt = 0;
    my $dir = $this->{INDEX_DIR};
    opendir(DIR, $dir);
    foreach my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next if $d !~ /idx(\d+).$this->{TYPE}.dat$/;
	my $id = $1;

	# ファイル(idx*.dat)をオープンする
	$this->{IN}[$fcnt] = new FileHandle;
	open($this->{IN}[$fcnt], "< $dir/idx$id.$this->{TYPE}.dat") or die "$dir/idx$id.$this->{TYPE}.dat: $!\n";
	$fcnt++;
    }
    closedir(DIR);

    my @docs = undef;
    ## idxごとに検索
    for (my $f_num = 0; $f_num < $fcnt; $f_num++) {
	my $offset = $this->{OFFSET}[$f_num]->{$keyword->{string}};
	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}
	
	seek($this->{IN}[$f_num], $offset, 0);
	
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
		print STDERR "$host> keyword=$keyword->{string},ldf=$ldf\n" if ($this->{VERBOSE});
#		printf "ldf  = %d Byte.\n", (total_size($ldf));

		# 文書IDと出現頻度(tf)の取得
		for (my $j = 0; $j < $ldf; $j++) {
		    read($this->{IN}[$f_num], $buf, 4);
		    my $did = unpack('L', $buf);
#,		    printf "$did  = %d Byte.\n", (total_size($did));

		    read($this->{IN}[$f_num], $buf, 4);
#		    my $freq = unpack('L', $buf);
 		    my $freq = unpack('f', $buf);
		    printf "freq = %d Byte.\n", (total_size($freq));

		    unless ($this->{SKIPPOS}) {
			read($this->{IN}[$f_num], $buf, 4);
			my $size = unpack('L', $buf);
#			my $size = $freq;
			
			if (!exists($already_retrieved_docs->{$did}) && $add_flag < 1) {
			    seek($this->{IN}[$f_num], $size * 4, 1);
			} else {
			    $already_retrieved_docs->{$did} = 1;
			    
			    my @pos = ();
			    if ($no_position < 0) {
				seek($this->{IN}[$f_num], $size * 4, 1);
			    } else {
				for (my $k = 0; $k < $size; $k++) {
				    read($this->{IN}[$f_num], $buf, 4);
				    my $p = unpack('L', $buf);
				    push(@pos, $p);
				}
			    }
			}
		    }

		    if ($no_position < 0) {
			push(@docs, {did => $did, qid_freq => [{qid => $keyword->{qid}, freq => $freq}]});
		    } else {
			push(@docs, {did => $did, qid_freq => [{qid => $keyword->{qid}, freq => $freq}], $freq, pos => \@pos});
		    }
		    printf "docs %d Byte.\n", (total_size(\@docs));
		    print "-----\n";
		    exit if ($j > 2);
		}
		last;
	    }
	}
    }

    return \@docs;
}   

sub DESTROY {
    my ($this) = @_;

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	untie %{$this->{OFFSET}[$f_num]};
    }
}

1;
