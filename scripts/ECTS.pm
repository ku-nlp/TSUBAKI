package ECTS;

# $Id$

# 拡張同位表現集合 (Expaned Coordinate Term Set)


use strict;
use utf8;
use CDB_File;
use FileHandle;
use Trie;
use Juman;

# コンストラクタ
sub new {
    my ($clazz, $opt) = @_;

    my %this = ();

    $this{opt}   = $opt;
    $this{juman} = new Juman();

    if ($opt->{create}) {
	&init4create (\%this, $opt);
    } else {
	&init4retrieve (\%this, $opt);
    }

    bless \%this;
}

# デストラクタ
sub DESTROY {
    my ($this) = @_;

    $this->clear();
}

##############################################################
# 初期化メソッド(検索用)
##############################################################

sub init4retrieve {
    my ($this, $opt) = @_;

    &loadTerm2ID ($this, $opt->{term2id});

    &loadTrieDB ($this, $opt->{triedb});

    &loadBinaryData ($this, $opt->{bin_file}, $opt->{size_of_on_memory});
}

# 拡張同位表現（バイナリ）データのロード
sub loadBinaryData {
    my ($this, $file, $size_of_on_memory) = @_;

    open ($this->{binaryDat}, $file) or die $!;
    if ($size_of_on_memory > 0) {
	# メモリ上に
	read ($this->{binaryDat}, $this->{binaryDatOnMemory}, $size_of_on_memory);
    }
}


# term2id ファイルのロード
sub loadTerm2ID {
    my ($this, $file) = @_;

    open (F, '<:utf8', $file) or die $!;
    while (<F>) {
	chop;

	my ($term, $id) = split (/ /, $_);
	$this->{term2id}{$term} = $id;
	$this->{id2term}{$id} = $term;
    }
    close (F);
}

# バイナリデータを操作する際に必要なオフセット、バイト長データを収めた Trie のロード
sub loadTrieDB {
    my ($this, $file) = @_;

    $this->{trie} = new Trie({usejuman => 1, userepname => 1});
    $this->{trie}->RetrieveDB($file);
}



##############################################################
# 初期化メソッド(データ構築用)
##############################################################

sub init4create {
    my ($this, $opt) = @_;

    $this->{id}      = 0;
    $this->{size}    = 0;
    $this->{keys}    = ();
    $this->{id2term} = ();
    $this->{term2id} = ();

    $this->{trie}    = new Trie({usejuman => 1, userepname => 1});

    &openTempFile($this);
    &openDFDB($this, $opt->{dfdb});
}

# Tempファイルの作成
sub openTempFile {
    my ($this) = @_;
    $this->{tmpf_path} = "_tmp.ecs.$$";
    # 読み/書き兼用で open
    $this->{tmpf} = new FileHandle(sprintf ("+> %s", $this->{tmpf_path})) or die $!;
}

# 複合名詞の文書頻度DBの tie
sub openDFDB {
    my ($this, $file) = @_;

    tie %{$this->{dfdb}}, 'CDB_File', $file or die $!;
}



##############################################################
# 検索用メソッド
##############################################################

# $query の拡張同位表現を得る
sub retrieve {
    my ($this, $query) = @_;

    my @terms;
    my @mrphs = $this->{juman}->analysis($query)->mrph();
    $this->{trie}->DetectString(\@mrphs, undef, { output_juman => 1, add_end_pos => 1 });
    my ($infos, $head) = ($mrphs[-1]->imis() =~ m!情報:(.+?)/主辞:([^:]+)!);

    foreach my $info (split (/@/, $infos)) {
	my ($id, $offset, $length) = ($info =~ /id=(\d+),off=(\d+),len=(\d+)/);
	my $buf = $this->read($offset, $length);
	my @_terms;
	while (my ($tid, $val) = each %$buf) {
	    push (@_terms, $this->{id2term}{$tid});
	}
	push (@terms, \@_terms);
    }

    return \@terms;
}

# $term の termID を返す
sub term2id {
    my ($this, $term) = @_;

    return $this->{term2id}{$term};
}

# $tid の midasi を返す
sub id2term {
    my ($this, $tid) = @_;

    return $this->{id2term}{$tid};
}

# 言語解析結果に対してオフセット情報を付与する
sub annotateDBInfo {
    my ($this, $annotation, $opt) = @_;

    my $resultObj;
    if ((ref $annotation) eq 'KNP::Result') {
	$resultObj = $annotation;
    } elsif ($opt->{juman_result}) {
	$resultObj = new Juman::Result ($annotation);
    }
    elsif ($opt->{knp_result}) {
	$resultObj = new KNP::Result ($annotation);
    }
    my @mrphs = $resultObj->mrph;
    $this->{trie}->DetectString(\@mrphs, undef, { output_juman => 1, add_end_pos => 1 });

    return $resultObj->all_dynamic;
}

# キャッシュのクリア
sub clear {
    my ($this) = @_;

    $this->{cache} = ();
}

# バイナリデータから同位表現IDを得る
sub read {
    my ($this, $offset, $length) = @_;

    # キャッシュになければ
    unless (exists $this->{cache}{$offset}) {
	my $_buf;
	if ($offset + $length < $this->{opt}{size_of_on_memory}) {
	    # メモリから
	    $_buf = substr ($this->{binaryDatOnMemory}, $offset, $length);
	} else {
	    # ディスクから
	    seek ($this->{binaryDat}, $offset, 0);
	    read ($this->{binaryDat}, $_buf, $length);
	}

	my %tids = ();
	foreach my $id (unpack ('L*', $_buf)) {
	    $tids{$id} = 1;
	}
	# キャッシング
	$this->{cache}{$offset} = \%tids;
    }

    return $this->{cache}{$offset};
}



##############################################################
# 構築用メソッド
##############################################################

# term と その同位表現の登録
sub add {
    my ($this, $_term, $coords) = @_;

    # term の正規化
    my $term = $this->normalize($_term);

    # term の登録
    $this->addNewTerm($term);

    my @buf;
    my $binaryDat = '';
    foreach my $_coord (split (/,/, $coords)) {
	my $coord = $this->normalize($_coord);
	$this->addNewTerm($coord);
	push (@buf, $this->{term2id}{$coord});
    }

    # sort してからバイナリ化
    my $prev = -1;
    foreach my $tid (sort {$a <=> $b} @buf) {
	if ($prev != $tid) {
	    $binaryDat .= pack ('L', $tid);
	}
	$prev = $tid;
    }
    # tmp ファイルへの書き出し
    $this->{tmpf}->print($binaryDat);

    push (@{$this->{keys}}, {midasi => $term,
			     id     => $this->{term2id}{$term},
			     df     => $this->getDF($term),
			     offset => $this->{size},
			     length => length ($binaryDat)});

    $this->{size} += length ($binaryDat);
}

# term の正規化（読み、語義IDの削除）
sub normalize {
    my ($this, $term) = @_;

    $term =~ s/:.+$//;
    $term =~ s!/.+$!!;

    return $term;
}

# term に対して id を振る
sub addNewTerm {
    my ($this, $term) = @_;

    unless (exists $this->{term2id}{$term}) {
	$this->{id2term}{$this->{id}} = $term;
	$this->{term2id}{$term} = $this->{id};
	$this->{id}++;
    }
}

# データ構築を終了する
sub close {
    my ($this, $opt) = @_;

    # tmp ファイルを見出しのDF順（降順）に sort して最終的なデータを作成
    $this->sortData($this->{opt});
    $this->finalize();
}

# tmp ファイルを見出しのDF順（降順）に sort して最終的なデータを作成
sub sortData {
    my ($this, $opt) = @_;

    # バッファの内容を書きだす
    $this->{tmpf}->flush();

    my ($buf, $offset, $prev, @info) = ('', 0, undef, ());
    open (BINARY, "> $opt->{bin_file}") or die $!;
    foreach my $term (sort {$b->{df} <=> $a->{df} ||
				$b->{id} <=> $a->{id}} @{$this->{keys}}) {
	$this->{tmpf}->seek($term->{offset}, 0);
	$this->{tmpf}->read($buf, $term->{length});
	print BINARY $buf;

	if (defined $prev && $prev->{id} != $term->{id}) {
	    $this->pushbackToTrie($prev->{midasi}, \@info);
	    @info = ();
	}
	push (@info, sprintf ("id=%s,off=%s,len=%s", $term->{id}, $offset, $term->{length}));
	$offset += $term->{length};

	$prev->{midasi} = $term->{midasi};
	$prev->{id} = $term->{id};
    }
    # for the last item
    $this->pushbackToTrie($prev->{midasi}, \@info);
    $this->{trie}->MakeDB($opt->{triedb});
    close (BINARY);


    open (TERM2ID, '>:utf8', $opt->{term2id}) or die $!;
    while (my ($term, $id) = each %{$this->{term2id}}) {
	print TERM2ID $term . ' ' . $id . "\n";
    }
    close (TERM2ID);
}

# trie への書き出し
sub pushbackToTrie {
    my ($this, $midasi, $_info) = @_;

    my @mrph = $this->{juman}->analysis($midasi)->mrph;
    my $head = $this->normalize($mrph[-1]->repnames);
    my $info = sprintf ("情報:%s/主辞:%s", join ("@", @$_info), $head);

    $this->{trie}->Add($midasi, $info);
}

# 後処理
sub finalize {
    my ($this) = @_;

    close($this->{tmpf});
    unlink $this->{tmpf_path};
    untie %{$this->{dfdb}};
}

# 文書頻度を返す
sub getDF {
    my ($this, $term) = @_;

    my $df = $this->{dfdb}{$term};
    return (defined $df) ? $df : 0;
}

1;
