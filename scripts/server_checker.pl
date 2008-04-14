#!/usr/bin/env perl

# TSUBAKIのサーバープログラムが動作しているかどうかを確認するプログラム

use strict;
use utf8;
use IO::Socket;
use IO::Select;
use Configure;
use Error qw(:try);
use Getopt::Long;

my (%opt);
GetOptions(\%opt, 'syngraph', 'snippet', 'verbose');

my $CONFIG = Configure::get_instance();

my $servers = $CONFIG->{SEARCH_SERVERS};
$servers = $CONFIG->{SEARCH_SERVERS_FOR_SYNGRAPH} if ($opt{syngraph});
$servers = $CONFIG->{STANDARD_FORMAT_LOCATION} if ($opt{snippet});

my $selecter = IO::Select->new();
my $num_of_sockets = 0;
foreach my $s (@$servers) {
    try {
	# 問い合わせ
	my $socket = IO::Socket::INET->new(PeerAddr => $s->{name}, PeerPort => $s->{port}, Proto => 'tcp');
	$selecter->add($socket) or die "Cannot connect to the server $s->{name}:$s->{port}. $!\n";

	print $socket "IS_ALIVE\n";
	$socket->flush();
	$num_of_sockets++;
    } catch Error with {
	my $err = shift;
	printf ("Cannot connect to the server %s:%s.\n", $s->{name}, $s->{port});
	printf ("Exception at line %s in %s\n", $err->{-line}, $err->{-file}) if ($opt{verbose});
    };
}


# 結果の受信
while ($num_of_sockets > 0) {
    my ($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
    foreach my $socket (@{$readable_sockets}) {
	my $buff = undef;
	while (<$socket>) {
	    print $_;
	    last;
	}

	$selecter->remove($socket);
	$socket->close();
	$num_of_sockets--;
    }
}
