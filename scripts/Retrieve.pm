package Retrieve;

# $Id$

###################################################################
# 与えられた単語を含む文書IDをindex<NAME>.datから検索するモジュール
###################################################################

use strict;
use BerkeleyDB;
use Encode;
use utf8;
use FileHandle;

sub new {
    my ($class, $dir) = @_;

    my $this = {IN => [], OFFSET => [], FILE_NUM => 0};

    # idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
    opendir(DIR, $dir) or die "$dir: $!\n";

    for my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next if $d !~ /idx(.+).dat/;
	my $NAME = $1;

	# ファイル(idx*.dat)をオープンする
	$this->{IN}[$this->{FILE_NUM}] = new FileHandle;
	open($this->{IN}[$this->{FILE_NUM}], "< $dir/idx$NAME.dat") or die "$dir/idx$NAME.dat: $!\n";

	# OFFSET(offset*.dat)を読み込み専用でtie
	my $table =  tie %{$this->{OFFSET}[$this->{FILE_NUM}]}, 'BerkeleyDB::Hash', -Filename => "$dir/offset$NAME.db", -Flags => DB_RDONLY or die "$!\n";
	&_encode_db($table);
	$this->{FILE_NUM}++;
    }

    bless $this;
}

sub search {
    my ($this, $key) = @_;

    my @query_list = split(/[\s　]+/, $key);
    my @dlist;
    my @result = ();

    # 各キーワードを含む文書IDを、@dlistに入れる
    # @dlistは配列のリファレンスの配列

    # 読み込みファイルごとに処理
    for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {

	@dlist = ();
	for (my $k = 0; $k < @query_list; $k++) {
	    my $query = $query_list[$k];
	    next unless defined $this->{OFFSET}[$f_num]{$query};
	    seek($this->{IN}[$f_num], $this->{OFFSET}[$f_num]{$query}, 0);

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
		    my $size = unpack('L', $buf);
		    ### sizeをおぼえる

		    # 文書IDと出現頻度
		    for (my $i = 0; $i < $size; $i++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $did = unpack('L', $buf);
			read($this->{IN}[$f_num], $buf, 4);
			my $freq = unpack('L', $buf);
			push (@{$dlist[$k]}, {"did" => $did, "freq" => $freq});
		    }
		    last;
		}
	    }
	}

	if (@dlist) {
	    push(@result, &_calc_d_score(@dlist));
	}
    }

    return @result;
}

sub DESTROY {
    my ($this) = @_;

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {
	$this->{IN}[$f_num]->close;
	untie %{$this->{OFFSET}[$this->{FILE_NUM}]};
    }
}


# 文書IDごとのスコアを計算

sub _calc_d_score {

    my (@kid2did_frep) = @_;
    my (@result) = ();

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)
    my @tmp = sort {scalar(@{$a}) <=> scalar(@{$b})} @kid2did_frep;
    @kid2did_frep = @tmp;

    # 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
    for (my $d = 0; $d < @{$kid2did_frep[0]}; $d++) {

	# 対象の文書を含まない配列があった場合
	# $error_flagが立ったまま以下のループを終了する
	my $flag;

	# 一番短かい配列以外を順に調べる
	for (my $k = 1;  $k < @kid2did_frep; $k++) {
	    $flag = 1; 

	    while (@{$kid2did_frep[$k]}) {

		if ($kid2did_frep[$k][0]{did} < $kid2did_frep[0][$d]{did}) {
		    shift(@{$kid2did_frep[$k]});
		}
		elsif ($kid2did_frep[$k][0]{did} == $kid2did_frep[0][$d]{did}) {
		    $flag = 0;
		    last;
		}
		elsif ($kid2did_frep[$k][0]{did} > $kid2did_frep[0][$d]{did}) {
		    last;
		}
	    }
	    last if ($flag);
	}
	push(@result, $kid2did_frep[0][$d]) if (!$flag);
    }
    return @result;
}

# データベースのエンコード設定
sub _encode_db {
    my ($db) = @_;
    $db->filter_fetch_key(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_key(sub {$_ = &encode('euc-jp', $_)});
    $db->filter_fetch_value(sub {$_ = &decode('euc-jp', $_)});
    $db->filter_store_value(sub {$_ = &encode('euc-jp', $_)});
}

1;
