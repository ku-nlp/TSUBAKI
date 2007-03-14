package Binarizer;

#############################################################
# idxファイルをバイナリ化するクラス(オフセット値も同時に保存)
#############################################################

use strict;
use CDB_File;
use Encode;
use FileHandle;

sub new {
    my($class, $th, $datfp, $cdbfp) = @_;
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
		odbcnt => 0};

    bless $this;
}

sub close {
    my ($this) = @_;
    $this->{odb}->finish();
    $this->{dat}->close();
#   print STDERR "$this->{totalbytes}\n";
}

sub DESTROY {
    my($this) = @_;
#   $this->{odb}->finish();
#   $this->{dat}->close();
}

sub add {
    my($this, $index, $docs) = @_;

    my $dlength = scalar(@{$docs});
    return if($dlength < $this->{threshold});

    # UTFエンコードされた単語を出力
    my $index_utf8 = encode('utf8', $index);
    print {$this->{dat}} $index_utf8;

    # 0を出力
    print {$this->{dat}} pack('c', 0);
#   print {$this->{dat}} ':0:';

    # 文書数をlong型で出力
    print {$this->{dat}} pack('L', $dlength);
#   print {$this->{dat}} "$dlength:";

    for(my $i = 0; $i < $dlength; $i++) {
 	my ($did, $freq) = split (/:/, $docs->[$i]);

 	# 単語IDと頻度をLONGで出力
	print {$this->{dat}} pack('L', $did);
	print {$this->{dat}} pack('L', $freq);
# 	print {$this->{dat}} "$did:";
# 	print {$this->{dat}} "$freq:";
    }
#   print {$this->{dat}} "\n";

    # オフセットを保存し、下の処理で書き込むバイト数分増やす
    $this->{totalbytes} += (length($index_utf8) + length("$this->{offset}"));
    if($this->{totalbytes} > 1800000000){
	$this->{odb}->finish();
	$this->{odbcnt}++;
	$this->{odb} = new CDB_File ("$this->{odbfp}.$this->{odbcnt}", "$this->{odbfp}.$this->{odbcnt}.$$") or die;
	$this->{totalbytes} = 0;
    }

    $this->{odb}->insert($index, $this->{offset});
    $this->{offset} += (length($index_utf8) + 5 + 8 * $dlength);
}

1;
