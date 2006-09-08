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
    my $undef_flag; # すべてのoffsetに存在しないキーワードがあった場合に1となる

    # 各キーワードを含む文書IDを、@dlistに入れる
    # @dlistは配列のリファレンスの配列
    for (my $id = 0; $id < @query_list; $id++) {
	my $query = $query_list[$id];
	$undef_flag = 1;
	# 読み込みファイルごとに探す
	for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {
	    next unless defined $this->{OFFSET}[$f_num]{$query};

	    $undef_flag = 0;
	    seek($this->{IN}[$f_num], $this->{OFFSET}[$f_num]{$query}, 0);

	    my $char;
	    my @str;
	    my $buf;
	    while (read($this->{IN}[$f_num], $char, 1)) {
		if (unpack('c', $char) == 0) {
		    $buf = join('', @str);
		    @str = ();

		    my $size;
		    read($this->{IN}[$f_num], $size, 4);
		    $size = unpack('L', $size);
		    for (my $i = 0; $i < $size; $i++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $did = unpack('L', $buf);
			read($this->{IN}[$f_num], $buf, 4);
			my $freq = unpack('L', $buf);
			push (@{$dlist[$id]}, $did);
		    }
		    last;
		}
		else {
		    push(@str, $char);
		}
	    }
	}
	if ($undef_flag) {
	    print "$query is undef.\n";
	    @dlist = ();
	    last;
	}
    }

    # 全てのキーワードを含む文書IDを取得
    if (@dlist) {
	return &_list_uniq(@dlist);
    }
    else {
	return ();
    }
}

sub DESTROY {
    my ($this) = @_;

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < $this->{FILE_NUM}; $f_num++) {
	$this->{IN}[$f_num]->close;
	untie %{$this->{OFFSET}[$this->{FILE_NUM}]};
    }
}

# 全てのキーワードを含む文書IDを取得
sub _list_uniq {
    my (@list) = @_;
    my (@result) = ();

    # 入力リストをサイズ順にソート(一番短い配列を先頭にするため)
    my @tmp = sort {scalar(@{$a}) <=> scalar(@{$b})} @list;
    @list = @tmp;

    # 各リストを文書IDが小さい順にソート
    for (my $l = 0; $l < @list; $l++) {
	my @tmp = sort {$a <=> $b} @{$list[$l]};
	@{$list[$l]} = @tmp;
    }

    # 一番短かい配列に含まれる文書が、他の配列に含まれるかを調べる
    for (my $i = 0; $i < @{$list[0]}; $i++) {

	# 対象の文書を含まない配列があった場合
	# $error_flagが立ったまま以下のループを終了する
	my $error_flag;

	# 一番短かい配列以外を順に調べる
	for (my $l_num = 1;  $l_num < @list; $l_num++) {
	    $error_flag = 1; 

	    while (@{$list[$l_num]}) {

		if ($list[$l_num][0] < $list[0][$i]) {
		    shift(@{$list[$l_num]});
		}
		elsif ($list[$l_num][0] == $list[0][$i]) {
		    $error_flag = 0;
		    last;
		}
		elsif ($list[$l_num][0] > $list[0][$i]) {
		    last;
		}
	    }
	    last if ($error_flag);
	}
	push(@result, $list[0][$i]) if (!$error_flag);
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
