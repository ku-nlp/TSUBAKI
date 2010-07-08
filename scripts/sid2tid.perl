#!/usr/bin/env perl

# 任意のデータのSID(UID)をTIDに変換するスクリプト
# Usage: $0 --sid2tid somewhere/sid2tid inputfile > outputfile

use strict;
use Getopt::Long;

our (%opt);
&GetOptions(\%opt, 'sid2tid=s');
$opt{sid2tid} = 'sid2tid' unless $opt{sid2tid};

our (%sid2tid, %uid2tid);
open(SID2TID, $opt{sid2tid}) or die "$opt{sid2tid}: $!\n";
while (<SID2TID>) {
    if (/^([-\d]+)\s+(\d+)/) {
	my ($sid, $tid) = ($1, $2);
	$sid2tid{$sid} = $tid;

	$sid =~ s/-\d+$//; # delete update number
	$uid2tid{$sid} = $tid; # register UID
    }
    else {
	warn "Invalid line in sid2tid: $_";
    }
}
close(SID2TID);

while (<>) {
    if (/^([-\d]+)\s+(.+)/) {
	my ($sid, $val) = ($1, $2);
	my $tid = &conv_sid2tid($sid);
	if ($tid) {
	    printf "%s %s\n", $tid, $val;
	}
    }
    else {
	warn "Invalid line in input: $_";
    }
}

sub conv_sid2tid {
    my ($sid) = @_;

    if ($sid =~ /-\d+$/) { # SID
	if (exists($sid2tid{$sid})) {
	    return $sid2tid{$sid};
	}
	else {
	    warn "SID <$sid>: not found\n";
	    return undef;
	}
    }
    else { # UID
	if (exists($uid2tid{$sid})) {
	    return $uid2tid{$sid};
	}
	else {
	    warn "UID <$sid>: not found\n";
	    return undef;
	}
    }
}
