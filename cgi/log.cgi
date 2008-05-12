#!/home/skeiji/local/bin/perl

# $Id$

use strict;
use utf8;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);

use Configure;
my $CONFIG = Configure::get_instance();

my @OPTs = ('query', 'start', 'results', 'logical_operator', 'dpnd', 'filter_simpages', 'only_hitcount', 'id', 'format');

open(LOG, "tac $CONFIG->{LOG_FILE_PATH} | head -300 |");
binmode(LOG, ':utf8');
print header(-charset => 'utf-8');

my $buf;
my $flag = 1;
my @attrs = ();

push(@attrs, 'DATE');
push(@attrs, 'HOST');
push(@attrs, 'ACCESS');

while (<LOG>) {
      my ($date, $host, $access, $options) = split(/ /, $_);

      $buf .= sprintf "<TR>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$date</TD>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$host</TD>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$access</TD>";
      foreach my $opt (split(/,/, $options)) {
	  my($k, $v) = split(/=/, $opt);
	  $buf .= sprintf "<TD style='border: 1px solid black;'>$v</TD>";
	  if ($flag) {
	      push(@attrs, $k);
	  }
      }
      $flag = 0;
      $buf .= sprintf "</TR>\n";
}
close(LOG);

my $hostname = `hostname` ; chop($hostname);
print "<H3>LOG on $hostname</H3>";
print "<HR>";

print "<TABLE style='border: 1px solid black;' width=*>";
print "<TR>";
foreach my $attr (@attrs) {
    print "<TD style='border: 1px solid black;'>$attr</TD>";
}
print "</TR>\n";
print $buf;
print "</TABLE>\n";

my @dates = ();
my %access = ();
open(LOG, "tac $CONFIG->{LOG_FILE_PATH} | head -3000 |");
while (<LOG>) {
    my($day,@etc) = split(/\-/, $_);
    next unless ($day =~ /^\d+$/);

    unless (exists($access{$day})) {
	push(@dates, $day);
	$access{$day} = 0;
    }
    $access{$day}++;
}
close(LOG);

print "<P>\n";
print "<TABLE>";
foreach my $day (@dates) {
    my $freq = 1 + $access{$day}/5;
    print "<TR><TD>$day</TD><TD>";
    for (my $i = 0; $i < $freq; $i++ ) {
	print "|";
    }
    print "</TD></TR>\n";
}
print "</TABLE>";
