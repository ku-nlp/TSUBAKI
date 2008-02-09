#!/home/skeiji/local/bin/perl

use strict;
use utf8;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);


my @OPTs = ('query', 'start', 'results', 'logical_operator', 'dpnd', 'filter_simpages', 'only_hitcount', 'id', 'format');

my $logfp = '/se_tmp/input.log';
open(LOG, "tac $logfp | head -100 |");

print header(-charset => 'utf-8');

my $hostname = `hostname` ; chop($hostname);
print "<H3>LOG on $hostname </H3>";
print "<HR>";

print "<TABLE style='border: 1px solid black;'>";
my @ATTRS = ('dpnd', 'filter_simpages', 'force_dpnd', 'logical_operator', 'near', 'only_hitcount', 'query', 'results', 'start', 'syngraph', 'hitcount', 'time');

print "<TR>";
print "<TD style='border: 1px solid black;'>date</TD>";
print "<TD style='border: 1px solid black;'>host</TD>";
print "<TD style='border: 1px solid black;'>method</TD>";
foreach my $attr (@ATTRS) {
    print "<TD style='border: 1px solid black;'>$attr</TD>";
}
print "</TR>\n";

while (<LOG>) {
      my($date,$host,$method,$options) = split(/ /, $_);

      print "<TR>";
      print "<TD style='border: 1px solid black;'>$date</TD>";
      print "<TD style='border: 1px solid black;'>$host</TD>";
      print "<TD style='border: 1px solid black;'>$method</TD>";
      my %opts = ();
      foreach my $opt (split(/,/, $options)) {
	  next if ($opt =~ /KEYS/);

	  my($k, $v) = split(/=/, $opt);
	  $opts{$k} = $v;
      }
      foreach my $k (@ATTRS) {
	  my $v = (exists $opts{$k}) ? $opts{$k} : 'null';
	  print "<TD style='border: 1px solid black;'>$v</TD>";
      }
      print "</TR>\n";
}
close(LOG);
print "</TABLE>";

my @dates = ();
my %access = ();
open(LOG, "tac $logfp | head -3000 |");
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
