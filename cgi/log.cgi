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
my @attrs = ();

push(@attrs, 'DATE');
push(@attrs, 'HOST');
push(@attrs, 'ACCESS');
push(@attrs, 'IS_CACHE');
push(@attrs, 'create_se_obj');
push(@attrs, 'hitcount');
push(@attrs, 'merge');
push(@attrs, 'miss_title');
push(@attrs, 'miss_url');
push(@attrs, 'parse_query');
push(@attrs, 'print_result');
push(@attrs, 'query');
push(@attrs, 'request_results_for_slave_server');
push(@attrs, 'search');
push(@attrs, 'send_query_to_server');
push(@attrs, 'get_result_from_server');
push(@attrs, 'normal_search');
push(@attrs, 'anchor_search');
push(@attrs, 'keyword_level_and_condition');
push(@attrs, 'force_dpnd_condition');
push(@attrs, 'near_condition');
push(@attrs, 'merge_dids');
push(@attrs, 'logical_condition');
push(@attrs, 'document_scoring');
push(@attrs, 'snippet_creation');
push(@attrs, 'total_docs');
push(@attrs, 'total');

while (<LOG>) {
      my ($date, $host, $access, @options) = split(/ /, $_);

      my %vals = ();
      foreach my $opt (split(/,/, join(' ', @options))) {
	  my($k, $v) = split(/=/, $opt);
	  $vals{$k} = $v;
      }

      $buf .= sprintf "<TR>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$date</TD>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$host</TD>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$access</TD>";

      foreach my $k (@attrs) {
	  next if ($k eq 'DATE' || $k eq 'ACCESS' || $k eq 'HOST');

	  if (exists $vals{$k}) {
	      $buf .= "<TD style='border: 1px solid black;' nowrap>$vals{$k}&nbsp;";
	      if (exists $vals{"max_$k"}) {
		  $buf .= qq(<SPAN style="color: red;">) . $vals{"max_$k"} . "</SPAN>\n";
	      }

	      if (exists $vals{"min_$k"}) {
		  $buf .= qq(<SPAN style="color: blue;">) . $vals{"min_$k"} . "</SPAN>\n";
	      }
	      $buf .= "</TD>\n";
	  } else {
	      $buf .= sprintf "<TD style='border: 1px solid black;' nowrap>none.</TD>";
	  }
      }
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
