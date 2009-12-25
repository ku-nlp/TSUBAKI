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

	# 00000-99 改訂番号を削除
	$sid =~ s/\-\d+$//g;

	$this->{SID2HOST}{$sid} = $host;
    }
    close (F);

    bless $this;
}

sub DESTROY {
}

sub lookup {
    my ($this, $did) = @_;

    # 00000-99 改訂番号を削除
    $did =~ s/\-\d+$//g;

    my $host = undef;
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
