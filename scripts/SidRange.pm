package SidRange;

# $Id$

# 標準フォーマットを管理しているホスト情報を管理するクラス

use strict;
use utf8;
use Configure;

my $CONFIG = Configure::get_instance();

sub new {
    my($class, $opt) = @_;

    my $this;
    my $rangefile = ($opt->{sid_range}) ? $opt->{sid_range} : $CONFIG->{SID_RANGE};
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

    bless $this;
}

sub DESTROY {
}

sub lookup {
    my ($this, $did) = @_;

    my $host = $this->{SID2HOST_FOR_UPDATE_NODE}{$did};
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
