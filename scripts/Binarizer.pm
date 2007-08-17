package Binarizer2;

#############################################################
# idxファイルをバイナリ化するクラス(オフセット値も同時に保存)
#############################################################

use strict;
use CDB_File;
use Encode;
use FileHandle;

sub new {
    my($class, $th, $datfp, $cdbfp, $position, $verbose) = @_;
    my $dat = new FileHandle;
    open($dat, "> $datfp") || die "$!\n";
    my $offset_cdb = new CDB_File ("$cdbfp", "$cdbfp.$$") or die;

    my $this = {
	offset => 0,
	odb => $offset_cdb,
	dat => $dat,
	odbfp => $cdbfp,
	datfp => $datfp,
	threshold => $th,
	totalbytes => 0,
	odbcnt => 0,
	position => $position,
	verbose => $verbose,
    };
    bless $this;
}

sub close {
    my ($this) = @_;
    $this->{odb}->finish();
    $this->{dat}->close();
}

sub DESTROY {
    my($this) = @_;
}

sub add {
    my($this, $index, $docs) = @_;

    my $dlength = scalar(@{$docs});
    return if($dlength < $this->{threshold});

    # UTFエンコードされた単語を出力
    my $index_utf8 = encode('utf8', $index);
    print {$this->{dat}} $index_utf8;
    print $index_utf8 if ($this->{verbose});

    # 0を出力
    print {$this->{dat}} pack('c', 0);
    print ':0:' if ($this->{verbose});

    # 文書数をlong型で出力
    print {$this->{dat}} pack('L', $dlength);
    print "$dlength:" if ($this->{verbose});

    my $did_bytes;
    my $frq_bytes;
    my $sid_bytes;
    my $pos_bytes;
    for(my $i = 0; $i < $dlength; $i++) {
 	my ($did, $freq_sid_pos) = split (/:/, $docs->[$i]);
	my ($freq, $sid_pos, @sids, @poss, $sids_size, $poss_size);
	if ($freq_sid_pos =~ /@/) {
	    ($freq, $sid_pos) = split (/@/, $freq_sid_pos);
	    my ($sids_str, $poss_str) = split(/\#/, $sid_pos);
	    @sids = split (/,/, $sids_str);
	    @poss = split (/,/, $poss_str);
	    $sids_size = scalar(@sids);
	    $poss_size = scalar(@poss);
	} else {
	    if ($this->{position}) {
		# position が指定されているのにインデックスの位置情報がない場合
		print STDERR "\nOption error!\n";
		print STDERR "Not found the locations of indexed terms.\n";
		print STDERR encode('euc-jp', "$index $docs->[$i]") . "\n";
#		exit(1);
	    }
	    $freq = $freq_sid_pos;
	}
	$did_bytes .= pack('L', $did);
	$frq_bytes .= pack('f', $freq);

	if ($this->{position}) {
	    my $prev;
	    my $buff;
	    my $cnt = 0;
#	    $sid_bytes .= pack('L', $sids_size);
	    foreach my $sid (@sids) {
		next if ($prev == $sid);
		$buff .= pack('L', $sid);
		$prev = $sid;
		$cnt++;
	    }
	    $sid_bytes .= pack('L', $cnt);
	    $sid_bytes .= $buff;

	    $cnt = 0;
	    my $buff2;
#	    $pos_bytes .= pack('L', $poss_size);
	    foreach my $pos (@poss) {
		next if ($prev == $pos);
		$buff2 .= pack('L', $pos);
		$prev = $pos;
		$cnt++;
	    }
	    $pos_bytes .= pack('L', $cnt);
	    $pos_bytes .= $buff2;
	}
    }

    # 各バイナリデータの書き込み
    print {$this->{dat}} $did_bytes;
    print {$this->{dat}} $frq_bytes;
    if ($this->{position}) {
	print {$this->{dat}} pack('L', length($sid_bytes));
	print {$this->{dat}} pack('L', length($pos_bytes));
	print {$this->{dat}} $sid_bytes;
	print {$this->{dat}} $pos_bytes;
    }

    # オフセットを保存し、下の処理で書き込むバイト数分増やす
    $this->{totalbytes} += (length($index_utf8) + length("$this->{offset}"));
    if($this->{totalbytes} > 1800000000){
	$this->{odb}->finish();
	$this->{odbcnt}++;
	$this->{odb} = new CDB_File ("$this->{odbfp}.$this->{odbcnt}", "$this->{odbfp}.$this->{odbcnt}.$$") or die;
	$this->{totalbytes} = 0;
    }

    $this->{odb}->insert($index, $this->{offset});

    $this->{offset} += length($index_utf8); # 索引語
    $this->{offset} += 1; # デリミタ0
    $this->{offset} += 4; # 文書頻度
    $this->{offset} += length($did_bytes); # 文書情報
    $this->{offset} += length($frq_bytes); # 文書頻度情報

    if ($this->{position}) {
	$this->{offset} += (4 + 4); # 文ID情報数サイズ + 出現位置情報サイズ
	$this->{offset} += length($sid_bytes); # 文ID情報
	$this->{offset} += length($pos_bytes); # 出現位置情報
    }
}

1;
