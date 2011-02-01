package SynGraphBinarizer;

# $Id$

#############################################################
# idxファイルをバイナリ化するクラス(オフセット値も同時に保存)
#############################################################

use strict;
use CDB_File;
use CDB_Writer;
use Encode;
use FileHandle;

our $FREQ_BIT_SIZE = 10;

sub new {
    my($class, $th, $datfp, $cdbfp, $position, $is_legacy_mode, $verbose, $is_32_bit_mode) = @_;
    my $dat = new FileHandle;
    open($dat, "> $datfp") || die "$!\n";
    my $cdbfp_base;
    if ($cdbfp =~ m|([^/]+)$|) {
	$cdbfp_base = $1; # basename
    }
    else {
	$cdbfp_base = $cdbfp;
    }
    my $MAX_DB_SIZE = ($is_32_bit_mode) ? 700000000 : 2500000000;
    my $offset_cdb1 = ($is_legacy_mode) ? undef : (new CDB_Writer ("$cdbfp", "$cdbfp_base.keymap", $MAX_DB_SIZE) or die);
    my $offset_cdb2 = ($is_legacy_mode) ? (new CDB_File ("$cdbfp", "$cdbfp.$$") or die) : undef;
    my $this = {
	offset => 0,
	odb => $offset_cdb1,
	odb_for_legacy => $offset_cdb2,
	dat => $dat,
	odbfp => $cdbfp,
	datfp => $datfp,
	threshold => $th,
	totalbytes => 0,
	odbcnt => 0,
	position => $position,
	is_legacy_mode => $is_legacy_mode,
	verbose => $verbose,
    };
    bless $this;
}

sub close {
    my ($this) = @_;
    $this->{odb_for_legacy}->finish() if (defined $this->{odb_for_legacy});
    $this->{odb}->close() if (defined $this->{odb});
    $this->{dat}->close();
}

sub DESTROY {
    my($this) = @_;
}

sub add {
    my ($this, $term, $docs) = @_;

    if ($this->{is_legacy_mode}) {
	$this->_add_for_legacy ($term, $docs);
    } else {
	$this->_add ($term, $docs);
    }
}

sub _add_for_legacy {
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
	$this->{odb_for_legacy}->finish();
	$this->{odbcnt}++;
	$this->{odb_for_legacy} = new CDB_File ("$this->{odbfp}.$this->{odbcnt}", "$this->{odbfp}.$this->{odbcnt}.$$") or die;
	$this->{totalbytes} = 0;
    }

    $this->{odb_for_legacy}->insert($index, $this->{offset});

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

sub _add {
    my($this, $term, $docs) = @_;

    my $num_of_docs = scalar(@{$docs});
    return if($num_of_docs < $this->{threshold});

    my $bindat = $this->text2binary ($term, $num_of_docs, $docs);

    # 各バイナリデータの書き込み
    print {$this->{dat}} $bindat;

    # オフセットを保存し、下の処理で書き込むバイト数分増やす
    $this->{odb}->add($term, $this->{totalbytes});
    $this->{totalbytes} += length($bindat);
}

# merge_sorted_idx.pl の出力ファイルをバイナリ化
sub text2binary {
    my ($this, $term, $num_of_docs, $docs) = @_;

    my ($bindat_dids, $bindat_features, $bindat_offs, $bindat_pos_freq_feature);
    for (my $i = 0; $i < $num_of_docs; $i++) {

	########################################################
	# テキストデータをデリミタを手掛かりに各データに分解する
	########################################################

	# フォーマット
	# s1029:値段 0181111770:0.99@109#1446&0.99&16 0181111823-1:1.98@164,176#1748&0.99&16,1868&0.99&16

 	my ($did, $totalfreq_sid_pos_freq_feature) = split (/:/, $docs->[$i]);
	my ($sid_pos_freq, @sids, @pos_frq_features);
	if ($totalfreq_sid_pos_freq_feature =~ /@/) {
	    my ($totalfreq, $sid_pos_freq_feature) = split (/@/, $totalfreq_sid_pos_freq_feature);
	    my ($sentenceID_str, $pos_freq_feature_str) = split(/\#/, $sid_pos_freq_feature);
	    @pos_frq_features = split (/,/, $pos_freq_feature_str);
	} else {
	    # position が指定されているのにインデックスの位置情報がない場合
	    print STDERR "\nOption error!\n";
	    print STDERR "Not found the locations of indexed terms.\n";
	    print STDERR encode('euc-jp', "$term $docs->[$i]") . "\n";
	    exit(1);
	}


	######################
	# バイナリデータの作成
	######################

	$bindat_dids .= pack('L', $did);
	my ($cnt, $feature, $buf) = (0, 0, '');
	foreach my $pos_frq_feature (@pos_frq_features) {
	    my ($_pos, $_freq, $_feature) = split(/\&/, $pos_frq_feature);
	    my $pos_frq =($_pos << $FREQ_BIT_SIZE) + int(1000 * $_freq);
	    $feature |= $_feature;
	    $buf .= pack('L', $_feature);
	    $buf .= pack('L', $pos_frq);
	    $cnt++;
	}
	$bindat_features .= pack('L', $feature);
	$bindat_offs .= pack('L', length($bindat_pos_freq_feature));
	$bindat_pos_freq_feature .= pack('L', $cnt);
	$bindat_pos_freq_feature .= $buf;
    }

    my $bindat = ((pack('L', $num_of_docs)) . $bindat_dids . $bindat_features . $bindat_offs . $bindat_pos_freq_feature);
    return (pack('L', length($bindat)) . $bindat);
}


1;
