package SidRange;

# $Id$

# 標準フォーマットを管理しているホスト情報を管理するクラス

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

    if (-f $opt->{sids_for_ntcir}) {
	require CDB_File;
	tie %{$this->{SID2HOST_FOR_NTCIR}}, 'CDB_File', $opt->{sids_for_ntcir} or die "$0: can't tie to $opt->{sids_for_ntcir} $!\n";
    }

    bless $this;
}

sub DESTROY {
    my ($this) = @_;

    if ($this->{SID2HOST_FOR_NTCIR}) {
	untie $this->{SID2HOST_FOR_NTCIR};
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

	return $this->{hashobj}->getnode($did);
    }
}

sub _lookup {
    my ($this, $did) = @_;

    my $host = $this->{SID2HOST_FOR_UPDATE_NODE}{$did};
    return $host if (defined $host);

    my $host = $this->{SID2HOST_FOR_NTCIR}{$did};
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
