package SidRange;

# $Id$

# 標準フォーマットを管理しているホスト情報を管理するクラス

# $opt->{sid_range} (default: $CONFIG->{SID_RANGE}): SIDの範囲に対するノード名を示したファイルを利用
# $opt->{sid_cdb} (default: $CONFIG->{SID_CDB}): SIDに対するノード名を示したCDBを利用
# $CONFIG->{USE_OF_HASH_FOR_SID_LOOKUP}: SIDをキーとするハッシュ関数を利用

use strict;
use utf8;
use Configure;

my $CONFIG = Configure::get_instance();

sub new {
    my($class, $opt) = @_;

    my $this = {};
    my $rangefile = ($opt->{sid_range}) ? $opt->{sid_range} : $CONFIG->{SID_RANGE};
    if ($rangefile) {
	open (F, $rangefile) or die "$!";
	while (<F>) {
	    chop;
	    my ($host, $sid) = split(/\s+/, $_);
	    last unless (defined $sid);


	    # 00000-99の99を削除
	    $sid =~ s/\-\d+$//g;

	    $this->{SID2HOST}{$sid} = $host;
	}
	close (F);
    }

    if (-f $opt->{sids_on_update_node}) {
	open (F, $opt->{sids_on_update_node}) or die "$!";
	while (<F>) {
	    chop;
	    my ($host, $sid) = split(/\s+/, $_);
	    last unless (defined $sid);

	    $this->{SID2HOST_FOR_UPDATE_NODE}{$sid} = $host;
	}
	close (F);
    }

    my $sid_cdb = $opt->{sid_cdb} ? $opt->{sid_cdb} : $CONFIG->{SID_CDB};
    if ($sid_cdb && -f $sid_cdb) {
	require CDB_File;
	tie %{$this->{SID_CDB}}, 'CDB_File', $opt->{sid_cdb} or die "$0: can't tie to $opt->{sid_cdb} $!\n";
    }

    my $nict2nii = $opt->{nict2nii} ? $opt->{nict2nii} : $CONFIG->{NICT2NII};
    if ($nict2nii && -f $nict2nii) {
	open (F, $nict2nii) or die "$!";
	while (<F>) {
	    chop;
	    my ($nictNode, $niiNode) = split(/\s+/, $_);

	    $this->{nict2nii}{sprintf ("%s.crawl.kclab.jgn2.jp", $nictNode)} = $niiNode;
	}
	close (F);
    }

    bless $this;
}

sub DESTROY {
    my ($this) = @_;

    if ($this->{SID_CDB}) {
	untie $this->{SID_CDB};
    }
}

sub lookup {
    my ($this, $did) = @_;

    unless ($CONFIG->{USE_OF_HASH_FOR_SID_LOOKUP}) {
	return $this->_lookup($did);
    } else {
	unless (defined $this->{hashobj}) {
	    require nict_hash;
	    $this->{hashobj} = new nict_hash();
	}

	if (defined $this->{nict2nii}) {
	    return $this->{nict2nii}{$this->{hashobj}->getnode($did)};
	} else {
	    return $this->{hashobj}->getnode($did);
	}
    }
}

sub _lookup {
    my ($this, $did) = @_;

    my $host = $this->{SID2HOST_FOR_UPDATE_NODE}{$did};
    return $host if (defined $host);

    $host = $this->{SID_CDB}{$did};
    return $host if (defined $host);

    # 00000-99の99を削除
    $did =~ s/\-\d+$//g;

    my $found = 0;
    foreach my $sid (sort {$a <=> $b} keys %{$this->{SID2HOST}}) {
	$host = $this->{SID2HOST}{$sid};
	if ($did <= $sid) {
	    return $host;
	}
    }

    return 'none';
}

1;
