#!/home/skeiji/local/bin/perl

# $Id$

use strict;
use utf8;
use Encode;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;
use POSIX qw(strftime);

my $DATF = "/home/skeiji/tsubaki/SearchEngine/data/questionnarie.dat";

&main();

sub main {
    # current time
    my $timestamp = strftime("%Y-%m-%d %T", localtime(time));
    
    my $cgi = new CGI();
    my $query = decode('utf8', $cgi->param('q'));
    my $judge = $cgi->param('question');
    my $msg = decode('utf8', $cgi->param('msg'));
    my $browser = $ENV{HTTP_USER_AGENT};
    $msg =~ s/\n/<BR>/g;

    open (WRITER, '>>:utf8', $DATF);
    printf WRITER ("%s\t%d\t%s\t%s\t%s\t%s\n", $timestamp, $judge, $query, $msg, $browser);
    close (WRITER);
}
