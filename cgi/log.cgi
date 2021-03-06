#!/home/skeiji/local/bin/perl
#!/share09/home/skeiji/local/bin/perl

# $Id$

use strict;
use utf8;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use Encode;
use URI::Escape;
use Configure;

use KNP;

my $CONFIG = Configure::get_instance();


my @OPTs = ('query', 'start', 'results', 'logical_operator', 'dpnd', 'filter_simpages', 'only_hitcount', 'id', 'format');

open(LOG, "tac $CONFIG->{LOG_FILE_PATH} | head -100 |");
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
push(@attrs, 'hitcount');
push(@attrs, 'total');
push(@attrs, 'query');
push(@attrs, 'create_se_obj') if ($OPTs{verbose});
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

my %history = ();
while (<LOG>) {
      my ($date, $host, $access, @options) = split(/ /, $_);
      # next if ($access eq 'API' && !$OPTs{verbose});
#      next if ($access eq 'API');

      my %vals = ();
      foreach my $opt (split(/,/, join(' ', @options))) {
	  my($k, $v) = split(/=/, $opt);
	  $v =~ s/~100w$//;
	  $vals{$k} = ($v eq '') ? undef : $v;
      }

#      next if ($vals{'status'} eq 'cache');


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
	      if ($k eq 'query') {
		  my $uri_encoded_query = &uri_escape(encode('utf8', $vals{$k} . "~100w"));
		  my $url = sprintf("%s?syngraph=1&start=1&query=%s", $CONFIG->{INDEX_CGI}, $uri_encoded_query);
		  # my $url = sprintf("%s?syngraph=1&start=1&q=%s", $CONFIG->{INDEX_CGI}, $uri_encoded_query);

		  $buf .= sprintf(qq(<TD style='border: 1px solid black; width: 20em;' nowrap><A target="_blank" href='%s'>%s&nbsp;), $url, $vals{$k});

		  $vals{$k} =~ s/~\d+.$//;
		  my $uri_encoded_query2 = &uri_escape(encode('utf8', $vals{$k} . "~100w"));
		  my $url2 = sprintf("http://tsubaki.ixnlp.nii.ac.jp/index.cgi?syngraph=1&start=0&q=%s",$uri_encoded_query2);
		  unless (exists $history{$vals{$k}}) {
		      my $hoge = "- [[$vals{$k}:$url2]]<BR>\n";
		      $hoge =~ s/ //g;
#		      print $hoge;
		      $history{$vals{$k}} = 1;
		  }
	      } else {
		  $buf .= "<TD style='border: 1px solid black;' nowrap>$vals{$k}&nbsp;";
	      }

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
print "[<A href='http://nlpc02.ixnlp.nii.ac.jp/log.cgi?verbose=1'>nlpc02</A>]&nbsp;";
print "[<A href='http://nlpc03.ixnlp.nii.ac.jp/log.cgi?verbose=1'>nlpc03</A>]&nbsp;";
print "[<A href='http://nlpc04.ixnlp.nii.ac.jp/log.cgi?verbose=1'>nlpc04</A>]&nbsp;";
print "[<A href='http://nlpc05.ixnlp.nii.ac.jp/log.cgi?verbose=1'>nlpc05</A>]&nbsp;";
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
