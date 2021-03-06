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
use Logger;
# use Devel::Size qw/size total_size/;
# use Devel::Size::Report qw/report_size/;
use Time::HiRes;
use Configure;


my $DEBUG = 1;
my $host = `hostname`; chop($host);
my $CONFIG = Configure::get_instance();

# $DEBUG = 1 if($host eq "nlpc01\n");

sub new {
    my ($class, $dir, $type, $skippos, $verbose, $dpnd, $show_speed) = @_;

    my $start_time = Time::HiRes::time;

    my $this = {
	IN => [],
	OFFSET => [],
	DOC_LENGTH => undef,
	TYPE => $type,
	INDEX_DIR => $dir,
	SKIPPOS => $skippos,
	verbose => $verbose,
	dpnd => $dpnd,
	SHOW_SPEED => $show_speed
    };

    my $fcnt = 0;
    # idx<NAME>.datおよび、対応するoffset<NAME>.dbのあるディレクトリを指定する
    opendir(DIR, $dir) or die "$dir: $!\n";
    for my $d (sort readdir(DIR)) {
	# idx*.datというファイルを読み込む
	next unless($d =~ /idx(.+?).$type.dat$/);
	next if ($d =~ /^a_/);
	my $NAME = $1;

	## OFFSET(offset*.dat)を読み込み専用でtie
	my $offset_fp = "$dir/offset$NAME.$type.cdb";
	print STDERR "$host> loading offset database ($offset_fp)...\n" if ($this->{verbose});
	tie %{$this->{OFFSET}[$fcnt][0]}, 'CDB_File', $offset_fp or die "$0: can't tie to $offset_fp $!\n";
	my $suffix = 1;
	while (-e "$offset_fp.$suffix") {
	    tie %{$this->{OFFSET}[$fcnt][$suffix]}, 'CDB_File', "$offset_fp.$suffix" or die "$0: can't tie to $offset_fp.$suffix $!\n";
	    print STDERR "$host> loading offset database ($offset_fp.$suffix)...\n" if ($this->{verbose});
	    $suffix++;
	}

	# idx*.datというファイルを読み込む
	next if $d !~ /idx(.+?).$this->{TYPE}.dat$/;
	my $id = $1;

	# ファイル(idx*.dat)をオープンする
	$this->{IN}[$fcnt] = new FileHandle;
	# print STDERR "$dir/idx$id.$this->{TYPE}.dat\n";
	open($this->{IN}[$fcnt], "< $dir/idx$id.$this->{TYPE}.dat") or die "$dir/idx$id.$this->{TYPE}.dat: $!\n";
	$fcnt++;
    }
    closedir(DIR);

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{SHOW_SPEED}) {
	printf ("@@@ %.4f sec. Retrieve's constructor calling.\n", $conduct_time);
    }

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



sub search_syngraph_test_for_new_format {
    my ($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search, $LOGGER) = @_;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    my $logger = new Logger();


    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}
	$logger->setTimeAs(sprintf ("get_offset_from_cdb_%s", $keyword->{string}), '%.3f');
	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}

	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
		$total_byte++;
	    }
	    else {
		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);

		# 13 = デリミタ(1) + ldf(4) + poss_size(4) + scores_size(4)
		$total_byte += (4 * $ldf + 13);

		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);

		my $offset4positions = $total_byte;
		my $offset4scores = $total_byte + $poss_size;
		my $index4positions = 0;
		my $pos = 0;
		my $begin = 0;
		my $total_pos = 0;
		foreach my $_i (0 .. $ldf - 1) {

 		    my $_buf = substr($buf, ($_i + $total_pos) * 4 , 4);
 		    my $num_of_positions = unpack('L', $_buf);

		    # 先のtermで検索された文書であれば登録（AND検索時）
		    if (exists $already_retrieved_docs->{$dids[$_i]}) {
			my $offset_j_pos = $offset_j + $pos++;

			$docs[$offset_j_pos]->[0] = $dids[$_i];
			$docs[$offset_j_pos]->[1] = $f_num;
			$docs[$offset_j_pos]->[2] = $num_of_positions;
			# 場所情報のオフセットを保存
			$docs[$offset_j_pos]->[3] = $offset4positions + ($_i + $total_pos + 1) * 4;
			# スコア情報のオフセットを保存
			$docs[$offset_j_pos]->[4] = $offset4scores + $total_pos * 2 + ($_i + 1) * 4;
		    }
		    $total_pos += $num_of_positions;
		}

		$offset_j += (scalar @docs);
		last;
	    }
	}
	$logger->setTimeAs(sprintf ("seektime_%s", $keyword->{string}), '%.3f');
    }

    foreach my $k ($logger->keys()) {
	$LOGGER->setParameterAs($k, $logger->getParameter($k));
    }

    return \@docs;
}

sub convert_to_new_index_data {
    my ($this, $keyword) = @_;

    my $data;
    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword};
	    last if (defined $offset);
	}
	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    next;
	}

	seek($this->{IN}[$f_num], $offset, 0);

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
	    }
	    else {
		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$data .= $buf;

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);
		$data .= $buf;

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);
		$data .= $buf;

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);
		$data .= $buf;

		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);
		$data .= $buf;

		# スコア情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $scores_size);
		$data .= $buf;
		$data = (pack('L', length($data)) . $data);
		last;
	    }
	}
    }

    return $data;
}

sub cut_data {
    my ($this, $keyword) = @_;

    my $data;
    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}
	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    next;
	}

	seek($this->{IN}[$f_num], $offset, 0);

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
		$data .= $buf;
	    }
	    else {
		$data .= $buf;

		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$data .= $buf;

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);
		$data .= $buf;

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);
		$data .= $buf;

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);
		$data .= $buf;

		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);
		$data .= $buf;

		# スコア情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $scores_size);
		$data .= $buf;
		last;
	    }
	}
    }

    return $data;
}

sub search_syngraph_test_for_new_format2 {
    my ($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search, $LOGGER) = @_;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    my $logger = new Logger();

    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}
	$logger->setTimeAs(sprintf ("get_offset_from_cdb_%s", $keyword->{string}), '%.3f');

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}
	
	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
		$total_byte++;
	    }
	    else {
		# デリミタ0の分
		$total_byte++;

		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$total_byte += 4;

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);

		my $pos = 0;
		my %soeji2pos = ();
		my $j = 0;
		foreach my $did (@dids) {
		    # 先のtermで検索された文書であれば登録（AND検索時）
		    if (exists $already_retrieved_docs->{$did}) {
			$docs[$offset_j + $pos]->[0] = $did;
			$soeji2pos{$j} = $pos++;
		    }
		    $j++;
		}
		$total_byte += (4 * $ldf);

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);
		$total_byte += 8;


		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);
		my @data = unpack('L*', $buf);

		for (my $pos = 0, my $soeji = 0, my $offset_j_pos = 0, my $index = 0; $soeji < $ldf; $soeji++) {
		    # 出現回数を読み込み
		    my $num_of_poss = $data[$index];
		    $index += (1 + $num_of_poss);

		    # AND検索によってはじかれた文書かどうかのチェック
		    if (exists $soeji2pos{$soeji}) {
			# 必要時に読み込むようにデータへのオフセットを記録
			$offset_j_pos = $offset_j + $pos++;
			$docs[$offset_j_pos]->[1] = $f_num;
			$docs[$offset_j_pos]->[2] = $num_of_poss;
			$docs[$offset_j_pos]->[3] = $total_byte + 4;
		    }

 		    $total_byte += (4 + ($num_of_poss * 4));
		}


		# 各出現位置でのスコアをインデックスデータから読み込む
		read ($this->{IN}[$f_num], $buf, $scores_size);
		for (my $pos = 0, my $soeji = 0, my $buf_offset = 0; $buf_offset < $scores_size; $soeji++) {
		    my $buff = substr ($buf, $buf_offset, 4);
		    my $num_of_scores = unpack('L', $buff);

		    # AND検索によってはじかれた文書かどうかのチェック
		    if (exists $soeji2pos{$soeji}) {
			# スコア情報のオフセットを保存
			$docs[$offset_j + $pos++]->[4] = $total_byte + $buf_offset + 4;
		    }
		    $buf_offset += (4 + $num_of_scores * 2);
		}

		$offset_j += (scalar keys %soeji2pos);
		last;
	    }
	}
	$logger->setTimeAs(sprintf ("seektime_%s", $keyword->{string}), '%.3f');
    }

    foreach my $k ($logger->keys()) {
	$LOGGER->setParameterAs($k, $logger->getParameter($k));
    }

    return \@docs;
}

sub search_syngraph_test_for_new_format_with_add_flag {
    my ($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search, $LOGGER) = @_;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    my $logger = new Logger();

    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}
	$logger->setTimeAs(sprintf ("get_offset_from_cdb_%s", $keyword->{string}), '%.3f');

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}

	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
		$total_byte++;
	    }
	    else {
		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);

		# 13 = デリミタ(1) + ldf(4) + poss_size(4) + scores_size(4)
		$total_byte += (4 * $ldf + 13);

		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);

		my $offset4positions = $total_byte;
		my $offset4scores = $total_byte + $poss_size;
		my $index4positions = 0;
		my $pos = 0;
		my $begin = 0;
		foreach my $did (@dids) {

 		    my $_buf = substr($buf, $begin, 4);
 		    my $num_of_positions = unpack('L', $_buf);
 		    $begin += (($num_of_positions + 1)* 4);

		    my $offset_j_pos = $offset_j + $pos++;

		    $docs[$offset_j_pos]->[0] = $did;
		    $docs[$offset_j_pos]->[1] = $f_num;
		    $docs[$offset_j_pos]->[2] = $num_of_positions;
		    # 場所情報のオフセットを保存
		    $docs[$offset_j_pos]->[3] = $offset4positions + 4;
		    # スコア情報のオフセットを保存
		    $docs[$offset_j_pos]->[4] = $offset4scores + 4;
		    $already_retrieved_docs->{$did} = 1;

 		    $offset4positions += (4 + $num_of_positions * 4);
		    $offset4scores += (4 + $num_of_positions * 2);
		    
		    last if ($CONFIG->{MAX_SIZE_OF_DOCS} > 0 && $pos >= $CONFIG->{MAX_SIZE_OF_DOCS});
		}

		$offset_j += (scalar @docs);
		last;
	    }
	}
	$logger->setTimeAs(sprintf ("seektime_%s", $keyword->{string}), '%.3f');
    }

    if (defined $LOGGER) {
	foreach my $k ($logger->keys()) {
	    $LOGGER->setParameterAs($k, $logger->getParameter($k));
	}
    }

    return \@docs;
}

sub search_syngraph_test_for_new_format_with_add_flag2 {
    my ($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search, $LOGGER) = @_;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    my $logger = new Logger();

    # idxごとに検索
    for (my $f_num = 0, my $num_of_offset_files = scalar(@{$this->{OFFSET}}); $f_num < $num_of_offset_files; $f_num++) {
	my $offset;
	for (my $i = 0, my $size = scalar(@{$this->{OFFSET}[$f_num]}); $i < $size; $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}
	$logger->setTimeAs(sprintf ("get_offset_from_cdb_%s", $keyword->{string}), '%.3f');

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}

	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $buf;
	while (read($this->{IN}[$f_num], $buf, 1)) {
	    if (unpack('c', $buf) != 0) {
		$total_byte++;
	    }
	    else {
		# デリミタ0の分
		$total_byte++;

		# termの文書頻度（100万文書中）
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$total_byte += 4;

		# 文書IDの読み込み
		read($this->{IN}[$f_num], $buf, 4 * $ldf);
		my @dids = unpack("L$ldf", $buf);

		my $pos = 0;
		my %soeji2pos = ();
		foreach my $did (@dids) {
		    $already_retrieved_docs->{$did} = 1;
		    $docs[$offset_j + $pos++]->[0] = $did;
		}
		$total_byte += (4 * $ldf);

		# 場所情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $poss_size = unpack('L', $buf);

		# スコア情報フィールドのバイト長を取得
		read($this->{IN}[$f_num], $buf, 4);
		my $scores_size = unpack('L', $buf);
		$total_byte += 8;


		# 場所情報をインデックスデータから読み込む
 		read($this->{IN}[$f_num], $buf, $poss_size);
		my @data = unpack('L*', $buf);

		for (my $pos = 0, my $soeji = 0, my $offset_j_pos = 0, my $index = 0; $soeji < $ldf; $soeji++) {
		    # 出現回数を読み込み
		    my $num_of_poss = $data[$index];
		    $index += (1 + $num_of_poss);

		    # 必要時に読み込むようにデータへのオフセットを記録
		    $offset_j_pos = $offset_j + $pos++;
		    $docs[$offset_j_pos]->[1] = $f_num;
		    $docs[$offset_j_pos]->[2] = $num_of_poss;
		    $docs[$offset_j_pos]->[3] = $total_byte + 4;

 		    $total_byte += (4 + ($num_of_poss * 4));
		}


		# 各出現位置でのスコアをインデックスデータから読み込む
		read ($this->{IN}[$f_num], $buf, $scores_size);
		for (my $pos = 0, my $soeji = 0, my $buf_offset = 0; $buf_offset < $scores_size; $soeji++) {
		    my $buff = substr ($buf, $buf_offset, 4);
		    my $num_of_scores = unpack('L', $buff);

		    # スコア情報のオフセットを保存
		    $docs[$offset_j + $pos++]->[4] = $total_byte + $buf_offset + 4;
		    $buf_offset += (4 + $num_of_scores * 2);
		}

		$offset_j += (scalar keys %soeji2pos);
		last;
	    }
	}
	$logger->setTimeAs(sprintf ("seektime_%s", $keyword->{string}), '%.3f');
    }

    foreach my $k ($logger->keys()) {
	$LOGGER->setParameterAs($k, $logger->getParameter($k));
    }

    return \@docs;
}

sub search_syngraph {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search) = @_;

    my $start_time = Time::HiRes::time;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    ## idxごとに検索
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	my $offset;
	for (my $i = 0; $i < scalar(@{$this->{OFFSET}[$f_num]}); $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}
	
	my $first_seek_time = Time::HiRes::time;
	seek($this->{IN}[$f_num], $offset, 0);
	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $first_seek_time;
	if ($this->{SHOW_SPEED}) {
	    printf ("@@@ %f sec. first seek time.\n", $conduct_time);
	}
	
	my $char;
	my @str;
	my $buf;
	my $time_buff = Time::HiRes::time;
	while (read($this->{IN}[$f_num], $char, 1)) {
	    if (unpack('c', $char) != 0) {
		push(@str, $char);
		$total_byte++;
	    }
	    else {
		# 最初はキーワード（情報としては冗長）
		$buf = join('', @str);
		$total_byte++;

		my $finish_time = Time::HiRes::time;
		my $conduct_time = $finish_time - $time_buff;
		if ($this->{SHOW_SPEED}) {
		    printf ("@@@ %f sec. read indexed keyword from dat file.\n", $conduct_time);
		}
		@str = ();

		$time_buff = Time::HiRes::time;
		# 次にキーワードの文書頻度
		read($this->{IN}[$f_num], $buf, 4);

		my $ldf = unpack('L', $buf);
		    
		# 文書IDと出現頻度(tf)の取得
		for (my $j = 0; $j < $ldf; $j++) {
		    read($this->{IN}[$f_num], $buf, 4);
		    my $did = unpack('L', $buf) + 0;
		    read($this->{IN}[$f_num], $buf, 4);
		    my $freq = unpack('L', $buf) / 10000;
		    push(@docs, [$did, $freq]);
		}
		last;
	    }
	}
    }

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{SHOW_SPEED}) {
	printf ("@@@ %.4f sec. search method calling in Retrieve.pm.\n", $conduct_time);
    }

    return \@docs;
}   

sub search_syngraph_with_position {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search) = @_;

    my $start_time = Time::HiRes::time;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    ## idxごとに検索
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	my $offset;
	for (my $i = 0; $i < scalar(@{$this->{OFFSET}[$f_num]}); $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}

	my $first_seek_time = Time::HiRes::time;
	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $first_seek_time;
	if ($this->{SHOW_SPEED}) {
	    printf ("@@@ %f sec. first seek time.\n", $conduct_time);
	}
	
	my $char;
	my @str;
	my $buf;
	my $time_buff = Time::HiRes::time;
	while (read($this->{IN}[$f_num], $char, 1)) {
	    if (unpack('c', $char) != 0) {
		push(@str, $char);
		$total_byte++;
	    }
	    else {
		# 最初はキーワード（情報としては冗長）
		$buf = join('', @str);
		$total_byte++;

		my $finish_time = Time::HiRes::time;
		my $conduct_time = $finish_time - $time_buff;
		if ($this->{SHOW_SPEED}) {
		    printf ("@@@ %f sec. read indexed keyword from dat file.\n", $conduct_time);
		}
		@str = ();

		$time_buff = Time::HiRes::time;
		# 次にキーワードの文書頻度
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$total_byte += 4;

		# 文書IDと出現頻度(tf)の取得
		for (my $j = 0; $j < $ldf; $j++) {
		    read($this->{IN}[$f_num], $buf, 4);
		    my $did = unpack('L', $buf) + 0;
		    $total_byte += 4;

		    read($this->{IN}[$f_num], $buf, 4);
		    my $freq = unpack('f', $buf);
		    $total_byte += 4;

		    read($this->{IN}[$f_num], $buf, 4);
		    my $size_of_sids_poss = unpack('L', $buf);
		    $total_byte += 4;

		    read($this->{IN}[$f_num], $buf, 4);
		    my $size_poss = unpack('L', $buf);
		    $total_byte += 4;

 		    seek($this->{IN}[$f_num], 4 * ($size_of_sids_poss - $size_poss), 1);
		    $total_byte += (4 * ($size_of_sids_poss - $size_poss));

		    push(@docs, [$did, $freq, $f_num, $total_byte, $size_poss]);

 		    seek($this->{IN}[$f_num], 4 * $size_poss, 1);
		    $total_byte += (4 * $size_poss);
		}
		last;
	    }
	}
    }

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{SHOW_SPEED}) {
	printf ("@@@ %.4f sec. search method calling in Retrieve.pm.\n", $conduct_time);
    }

    return \@docs;
}   

sub search_syngraph_with_position_dpnd {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $no_position, $sentence_flag, $syngraph_search) = @_;

    my $start_time = Time::HiRes::time;

    my $offset_j = 0;
    my @docs = ();
    my $total_byte = 0;
    ## idxごとに検索
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	my $offset;
	for (my $i = 0; $i < scalar(@{$this->{OFFSET}[$f_num]}); $i++) {
	    $offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
	    last if (defined $offset);
	}

	# オフセットがあるかどうかのチェック
	unless (defined($offset)) {
	    @docs = () unless (defined(@docs));
	    next;
	}

	my $first_seek_time = Time::HiRes::time;
	seek($this->{IN}[$f_num], $offset, 0);
	$total_byte = $offset;

	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $first_seek_time;
	if ($this->{SHOW_SPEED}) {
	    printf ("@@@ %f sec. first seek time.\n", $conduct_time);
	}
	
	my $char;
	my @str;
	my $buf;
	my $time_buff = Time::HiRes::time;
	while (read($this->{IN}[$f_num], $char, 1)) {
	    if (unpack('c', $char) != 0) {
		push(@str, $char);
		$total_byte++;
	    }
	    else {
		# 最初はキーワード（情報としては冗長）
		$buf = join('', @str);
		$total_byte++;

		my $finish_time = Time::HiRes::time;
		my $conduct_time = $finish_time - $time_buff;
		if ($this->{SHOW_SPEED}) {
		    printf ("@@@ %f sec. read indexed keyword from dat file.\n", $conduct_time);
		}
		@str = ();

		$time_buff = Time::HiRes::time;
		# 次にキーワードの文書頻度
		read($this->{IN}[$f_num], $buf, 4);
		my $ldf = unpack('L', $buf);
		$total_byte += 4;

		# 文書IDと出現頻度(tf)の取得
		for (my $j = 0; $j < $ldf; $j++) {
		    read($this->{IN}[$f_num], $buf, 4);
		    my $did = unpack('L', $buf) + 0;
		    $total_byte += 4;

		    read($this->{IN}[$f_num], $buf, 4);
		    my $freq = unpack('f', $buf);
		    $total_byte += 4;

		    read($this->{IN}[$f_num], $buf, 4);
		    my $size_poss = unpack('L', $buf);
		    $total_byte += 4;

		    push(@docs, [$did, $freq, $f_num, $total_byte, $size_poss]);

 		    seek($this->{IN}[$f_num], 4 * $size_poss, 1);
		    $total_byte += (4 * $size_poss);
		}
		last;
	    }
	}
    }

    my $finish_time = Time::HiRes::time;
    my $conduct_time = $finish_time - $start_time;
    if ($this->{SHOW_SPEED}) {
	printf ("@@@ %.4f sec. search method calling in Retrieve.pm.\n", $conduct_time);
    }

    return \@docs;
}

sub load_position {
    my ($this, $f_num, $offset, $size_poss, $opt) = @_;

    my $buf;
    seek ($this->{IN}[$f_num], $offset, 0);
    read ($this->{IN}[$f_num], $buf, $size_poss * 4);
    my @pos_list = unpack("L*", $buf);

    return \@pos_list;
}

sub load_score {
    my ($this, $f_num, $offset, $size_scores) = @_;

    my $buf;
    seek ($this->{IN}[$f_num], $offset, 0);
    read ($this->{IN}[$f_num], $buf, $size_scores * 2);
    my @score_list = map {$_ / 1000} unpack("S$size_scores", $buf);

    return \@score_list;
}

sub search {
    my ($this, $keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search, $logger) = @_;

    if ($add_flag) {
	return $this->search_syngraph_test_for_new_format_with_add_flag($keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search, $logger);
    } else {
	return $this->search_syngraph_test_for_new_format($keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search, $logger);
    }
}

sub search4syngraph {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search) = @_;
    return $this->search($keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search);
}

sub search4syngraph2 {
    my($this, $keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search) = @_;

    if ($syngraph_search) {
	if ($this->{dpnd} > 0) {
	    return $this->search_syngraph_with_position_dpnd($keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search);
	} else {
	    return $this->search_syngraph_with_position($keyword, $already_retrieved_docs, $add_flag, $only_hitcount, $sentence_flag, $syngraph_search);
	}
    } else {
	my $start_time = Time::HiRes::time;

	my $offset_j = 0;
	my @docs = ();
	my $total_byte = 0;
	## idxごとに検索
	for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	    my $offset;
	    for (my $i = 0; $i < scalar(@{$this->{OFFSET}[$f_num]}); $i++) {
		$offset = $this->{OFFSET}[$f_num][$i]->{$keyword->{string}};
		last if (defined $offset);
	    }

	    # オフセットがあるかどうかのチェック
	    unless (defined($offset)) {
		@docs = () unless (defined(@docs));
		next;
	    }
	    # print STDERR $offset . "=offset\n";

	    my $first_seek_time = Time::HiRes::time;
	    seek($this->{IN}[$f_num], $offset, 0);
	    my $finish_time = Time::HiRes::time;
	    my $conduct_time = $finish_time - $first_seek_time;
	    if ($this->{SHOW_SPEED}) {
		printf ("@@@ %f sec. first seek time.\n", $conduct_time);
	    }

	    my $char;
	    my @str;
	    my $buf;
	    my $time_buff = Time::HiRes::time;
	    while (read($this->{IN}[$f_num], $char, 1)) {
		if (unpack('c', $char) != 0) {
		    push(@str, $char);
		    $total_byte++;
		}
		else {
		    # 最初はキーワード（情報としては冗長）
		    $buf = join('', @str);
		    $total_byte++;

		    my $finish_time = Time::HiRes::time;
		    my $conduct_time = $finish_time - $time_buff;
		    if ($this->{SHOW_SPEED}) {
			printf ("@@@ %f sec. read indexed keyword from dat file.\n", $conduct_time);
		    }
		    @str = ();

		    $time_buff = Time::HiRes::time;
		    # 次にキーワードの文書頻度
		    read($this->{IN}[$f_num], $buf, 4);
		    my $ldf = unpack('L', $buf);
		    # print "$f_num $this->{TYPE} $ldf=ldf\n";

		    $total_byte += 4;

		    $finish_time = Time::HiRes::time;
		    $conduct_time = $finish_time - $time_buff;
		    if ($this->{SHOW_SPEED}) {
			printf ("@@@ %f sec. read df value from dat file.\n", $conduct_time);
		    }

		    my $did_idx = 0;
		    # print STDERR "$host> keyword=", encode('euc-jp', $keyword->{string}) . ",ldf=$ldf\n";# if ($this->{verbose});
		    for (my $j = 0; $j < $ldf; $j++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $did = unpack('L', $buf);
			$docs[$offset_j + $j]->[0] = $did;
		    }

		    for (my $j = 0; $j < $ldf; $j++) {
			read($this->{IN}[$f_num], $buf, 4);
			my $freq = unpack('f', $buf);
			$docs[$offset_j + $j]->[1] = $freq;
		    }

		    unless ($this->{SKIPPOS}) {
			print "only_hitcount = $only_hitcount\n";
			if ($only_hitcount < 1) {
			    read($this->{IN}[$f_num], $buf, 4);
			    my $sids_size = unpack('L', $buf);
			    read($this->{IN}[$f_num], $buf, 4);
			    my $poss_size = unpack('L', $buf);
			    my $total_bytes = 0;
			    if ($sentence_flag > 0) {
				for (my $i = 0; $total_bytes < $sids_size; $i++) {
				    read($this->{IN}[$f_num], $buf, 4);
				    my $size = unpack('L', $buf);
				    for (my $j = 0; $j < $size; $j++) {
					read($this->{IN}[$f_num], $buf, 4);
					push(@{$docs[$offset_j + $i]->[2]}, unpack('L', $buf));
				    }
				    $total_bytes += (($size + 1) * 4);
				}
			    } else {
				seek($this->{IN}[$f_num], $sids_size, 1);
				for (my $i = 0; $total_bytes < $poss_size; $i++) {
				    read($this->{IN}[$f_num], $buf, 4);
				    my $size = unpack('L', $buf);
				    my @poss = ();
				    for (my $j = 0; $j < $size; $j++) {
					read($this->{IN}[$f_num], $buf, 4);
					my $p = unpack('L', $buf);
					push(@poss, $p);
				    }
				    $docs[$offset_j + $i]->[2] = \@poss;
				    $total_bytes += (($size + 1) * 4);
				}
			    }
			}
		    }
		    $offset_j += $ldf;
		    last;
		}
	    }
	}

	my $finish_time = Time::HiRes::time;
	my $conduct_time = $finish_time - $start_time;
	if ($this->{SHOW_SPEED}) {
	    printf ("@@@ %.4f sec. search method calling in Retrieve.pm.\n", $conduct_time);
	}

	return \@docs;
    }
}

sub DESTROY {
    my ($this) = @_;

    foreach my $fh (@{$this->{IN}}) {
	close($fh);
    }

    # ファイル(idx*.dat)をクローズ、OFFSET(offset*.dat)をuntieする
    for (my $f_num = 0; $f_num < scalar(@{$this->{OFFSET}}); $f_num++) {
	untie %{$this->{OFFSET}[$f_num]};
    }
}

1;
