package Binarizer;

#$Id;$

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
    my $totalfreq_bytes;
    my $sid_bytes;
    my $pos_bytes;
    my $frq_bytes;
    for (my $i = 0; $i < $dlength; $i++) {
 	my ($did, $totalfreq_sid_pos_freq) = split (/:/, $docs->[$i]);
	my ($totalfreq, $sid_pos_freq, @sids, @pos_frqs, $sids_size, $poss_size, $frqs_size);
	if ($totalfreq_sid_pos_freq =~ /@/) {
	    ($totalfreq, $sid_pos_freq) = split (/@/, $totalfreq_sid_pos_freq);
	    my ($sids_str, $pos_freq_str) = split(/\#/, $sid_pos_freq);

	    @sids = split (/,/, $sids_str);
	    @pos_frqs = split (/,/, $pos_freq_str);

	    $sids_size = scalar(@sids);
	    $poss_size = scalar(@pos_frqs);
	    $frqs_size = $poss_size;
	} else {
	    if ($this->{position}) {
		# position が指定されているのにインデックスの位置情報がない場合
		print STDERR "\nOption error!\n";
		print STDERR "Not found the locations of indexed terms.\n";
		print STDERR encode('euc-jp', "$index $docs->[$i]") . "\n";
#		exit(1);
	    }
	    $totalfreq = $totalfreq_sid_pos_freq;
	}
	$did_bytes .= pack('L', $did);
#	$totalfreq_bytes .= pack('S', int(1000 * $totalfreq));

	if ($this->{position}) {
	    my $buff;
	    my $cnt = 0;
# 	    foreach my $sid (@sids) {
# 		$buff .= pack('L', $sid);
# 		$cnt++;
# 	    }
# 	    $sid_bytes .= pack('L', $cnt);
# 	    $sid_bytes .= $buff;

	    $cnt = 0;
	    my $buff2;
	    my $buff3;
	    foreach my $pos_frq (@pos_frqs) {
		my ($pos, $freq) = split(/\&/, $pos_frq);
		$buff2 .= pack('L', $pos);
		$buff3 .= pack('S', int(1000 * $freq));
		$cnt++;
	    }
	    $pos_bytes .= pack('L', $cnt);
	    $frq_bytes .= pack('L', $cnt);
	    $pos_bytes .= $buff2;
	    $frq_bytes .= $buff3;
	}
    }

    # 各バイナリデータの書き込み
    print {$this->{dat}} $did_bytes;
    if ($this->{position}) {
	print {$this->{dat}} pack('L', length($pos_bytes));
	print {$this->{dat}} pack('L', length($frq_bytes));
	print {$this->{dat}} $pos_bytes;
	print {$this->{dat}} $frq_bytes;
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

    if ($this->{position}) {
	$this->{offset} += (4 + 4); # 出現位置情報サイズ +  頻度情報サイズ
	$this->{offset} += length($pos_bytes); # 出現位置情報
	$this->{offset} += length($frq_bytes); # 頻度情報
    }
}

1;
