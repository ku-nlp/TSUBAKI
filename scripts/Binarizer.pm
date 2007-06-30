package Binarizer;

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

    my $this = {offset => 0,
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

    my $byte_pos = 0;
    for(my $i = 0; $i < $dlength; $i++) {
 	my ($did, $freq_pos) = split (/:/, $docs->[$i]);

	my ($freq, $pos_str, @poss, $size);
	if ($freq_pos =~ /@/) {
	    ($freq, $pos_str) = split (/@/, $freq_pos);
	    @poss = split (/,/, $pos_str);
	    $size = scalar(@poss);
	} else {
	    if ($this->{position}) {
		# position が指定されているのにインデックスの位置情報がない場合
		print STDERR "\nOption error!\n";
		print STDERR "Not found the locations of indexed terms.\n";
		exit(1);
	    }

	    $freq = $freq_pos;
	}

 	# 文書IDと頻度をLONGで出力
	print {$this->{dat}} pack('L', $did);
	print {$this->{dat}} pack('L', ($freq * 10000) + 0.5); # 四捨五入
 	print "$did:" . int(($freq * 10000) + 0.5) . " " if ($this->{verbose});

	if ($this->{position}) {
	    print {$this->{dat}} pack('L', $size);
	    print ":$size:" if ($this->{verbose});

	    foreach my $pos (@poss) {
		print {$this->{dat}} pack('L', $pos);
		print "$pos," if ($this->{verbose});
	    }
	    $byte_pos += ($size * 4);
	}
    }
    print "\n" if ($this->{verbose});

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
    $this->{offset} += (2 * 4 * $dlength); # (文書ID + 出現頻度) * 文書数

    if ($this->{position}) {
	$this->{offset} += (4 * $dlength); # 位置情報数 * 文書数
	$this->{offset} += $byte_pos; # 位置情報のサイズ
    }

#   printf ("offset: %s %d (next %d + %d + 4 + %d + %d)\n", $index_utf8, $this->{offset}, length($index_utf8), length('0'), (8 * $dlength), $byte_pos) if ($this->{verbose});
}

1;
