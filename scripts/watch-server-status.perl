#!/usr/bin/env perl

# $Id$

# TSUBAKIで利用しているサーバーの状態のログをとるプログラム

use strict;
use utf8;
use Net::Ping;
use Configure;


my $CONFIG = Configure::get_instance();
my $TIMEOUT = 5;

my @buf;
push (@buf, @{$CONFIG->{SEARCH_SERVERS}});
push (@buf, @{$CONFIG->{SEARCH_SERVERS_FOR_SYNGRAPH}});
push (@buf, @{$CONFIG->{SNIPPET_SERVERS}});

my %hosts = ();
foreach my $host (@buf) {
    $hosts{$host->{name}} = 1;
}

my $flag = 0;
my @downs;
my $P = Net::Ping->new();
open (F, "> $CONFIG->{SERVER_STATUS_LOG}") or die "$!";
foreach my $host (sort keys %hosts) {
    my $result = $P->ping($host, $TIMEOUT);
    # Pingの応答があった場合に、メッセージを表示
    if ($result){
	print F "$host is alive!\n";
    } else {
	print F "$host is down!\n";
	$flag = 1;
	push (@downs, $host);
    }
}
close (F);

# if ($flag) {
#     my $message = join ("\n", @downs);
#     my $hostname = `hostname | cut -f 1 -d .`; chop $hostname;
#     my $address = $CONFIG->{ADMINISTRATOR};
#     open (SENDMAIL, "| sendmail -t ");
#     print SENDMAIL << 'END';
# From: watch-server-status @ $hostname
# To: $address
# Subject: The following servers related to TSUBAKI are down!

# $message
# END
# close (SENDMAIL);
#     print STDERR "Sending mail to $CONFIG->{ADMINISTRATOR}.\n";
# }
