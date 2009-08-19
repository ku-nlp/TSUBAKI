#!/usr/bin/env perl

# $Id$

# 標準フォーマットを管理しているホストを調べる

use strict;
use utf8;
use Configure;
use Getopt::Long;

my $CONFIG = Configure::get_instance();

my (%opt);
GetOptions(\%opt, 'flist=s');

&main();

sub main {
    if ($opt{flist}) {
	open (READER, $opt{flist}) or die "$!";
	while (<READER>) {
	    chop;
	    my $file = $_;

	    my ($dir, $name) = ($file =~ /(.+?)\/([^\/]+)$/);
	    my ($did) = ($name =~ /^(\d+)/);

	    my $host = &lookup($did);
	    print $file . " " . $host . "\n";
	}
	close (READER);
    } else {
	foreach my $did (@ARGV) {
	    my $host = &lookup($did);
	    print $did . " " . $host . "\n";
	}
    }
}

sub lookup {
    my ($did) = @_;

    # 00000-99 改訂番号を削除
    $did =~ s/\-\d+$//g;

    my $host = undef;
    my $found = 0;
    foreach my $sid (sort {$a <=> $b} keys %{$CONFIG->{SID2HOST}}) {
	$host = $CONFIG->{SID2HOST}{$sid};
	if ($did <= $sid) {
	    return $host;
	}
    }

    return 'none';
}
