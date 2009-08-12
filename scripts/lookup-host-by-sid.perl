#!/usr/bin/env perl

use strict;
use utf8;
use Configure;

my $CONFIG = Configure::get_instance();


# 標準フォーマットを管理しているホストを調べる

foreach my $did (@ARGV) {
    # ★ 00000-99 改訂番号の扱い
    my $host = undef;
    foreach my $sid (sort {$a <=> $b} keys %{$CONFIG->{SID2HOST}}) {
	$host = $CONFIG->{SID2HOST}{$sid};
	last if ($did < $sid);
    }
    print $did . " " . $host . "\n";
}
