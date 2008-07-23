#!/home/skeiji/local/bin/perl

# $Id$

use strict;
use utf8;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);

use Configure;
my $CONFIG = Configure::get_instance();


my @OPTs = ('query', 'start', 'results', 'logical_operator', 'dpnd', 'filter_simpages', 'only_hitcount', 'id', 'format');

open(LOG, "tac $CONFIG->{LOG_FILE_PATH} | head -1000 |");
binmode(LOG, ':utf8');
print header(-charset => 'utf-8');

my $buf;
my @attrs = ();

my $cgi = new CGI;
my %OPTs;
$OPTs{verbose} = $cgi->param('verbose');


push(@attrs, 'DATE');
push(@attrs, 'HOST') if ($OPTs{verbose});
push(@attrs, 'ACCESS') if ($OPTs{verbose});
push(@attrs, 'status') if ($OPTs{verbose});
push(@attrs, 'portal') if ($OPTs{verbose});
push(@attrs, 'query');
push(@attrs, 'create_se_obj') if ($OPTs{verbose});
push(@attrs, 'hitcount');
push(@attrs, 'merge')  if ($OPTs{verbose});
# push(@attrs, 'miss_title');
# push(@attrs, 'miss_url');
push(@attrs, 'parse_query');
push(@attrs, 'print_result') if ($OPTs{verbose});
push(@attrs, 'request_results_for_slave_server') if ($OPTs{verbose});
push(@attrs, 'search');
push(@attrs, 'send_query_to_server') if ($OPTs{verbose});
push(@attrs, 'get_result_from_server') if ($OPTs{verbose});
push(@attrs, 'normal_search') if ($OPTs{verbose});
push(@attrs, 'anchor_search') if ($OPTs{verbose});
push(@attrs, 'keyword_level_and_condition') if ($OPTs{verbose});
push(@attrs, 'force_dpnd_condition') if ($OPTs{verbose});
push(@attrs, 'near_condition') if ($OPTs{verbose});
push(@attrs, 'merge_dids') if ($OPTs{verbose});
push(@attrs, 'logical_condition') if ($OPTs{verbose});
push(@attrs, 'document_scoring') if ($OPTs{verbose});
push(@attrs, 'snippet_creation');
# push(@attrs, 'total_docs') if ($OPTs{verbose});
push(@attrs, 'total');

while (<LOG>) {
      my ($date, $host, $access, @options) = split(/ /, $_);
      next if ($access eq 'API' && !$OPTs{verbose});
      next if ($_ =~ /0705\-124143/);
      next if ($_ =~ /total_docs=1420,total=96.783$/);

      my %vals = ();
      foreach my $opt (split(/,/, join(' ', @options))) {
	  my($k, $v) = split(/=/, $opt);
	  $v =~ s/~100w$//;
	  $vals{$k} = ($v eq '') ? undef : $v;
      }

      $buf .= sprintf "<TR>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$date</TD>";
      $buf .= sprintf "<TD style='border: 1px solid black;'>$host</TD>"  if ($OPTs{verbose});
      $buf .= sprintf "<TD style='border: 1px solid black;'>$access</TD>" if ($OPTs{verbose});

      foreach my $k (@attrs) {
	  next if ($k eq 'DATE' || $k eq 'ACCESS' || $k eq 'HOST');

	  if ($k eq 'status') {
	      $vals{$k} = qq(<FONT color="red">$vals{$k}</FONT>) if ($vals{$k} eq 'busy');
	      $vals{$k} = qq(<FONT color="green">$vals{$k}</FONT>) if ($vals{$k} eq 'cache');
	      $vals{$k} = qq(<FONT color="blue">$vals{$k}</FONT>) if ($vals{$k} eq 'search');
	  }

	  if (defined $vals{$k}) {
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
# print "<H3>QUERY LOG on $hostname</H3>";
print "<H3>QUERY LOG <FONT color=white>on $hostname</FONT></H3>";
print "<HR>";

print "<TABLE style='border: 1px solid black;' width=*>";
print "<TR>";
foreach my $attr (@attrs) {
    $attr =~ s/_/ /g;
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

# print "<P>\n";
# print "<TABLE>";
# foreach my $day (@dates) {
#     my $freq = 1 + $access{$day}/5;
#     print "<TR><TD>$day</TD><TD>";
#     for (my $i = 0; $i < $freq; $i++ ) {
# 	print "|";
#     }
#     print "</TD></TR>\n";
# }
# print "</TABLE>";
