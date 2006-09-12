#!/share/usr/bin/perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;

my $cgi = new CGI;
my $URL = $cgi->param('URL');
my $INPUT = $cgi->param('INPUT');
my $date = `date +%m%d-%H%M%S`;
chomp ($date);

my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", 
	     "880000", "00aa00", "886800", "004699", "990099");


my $retrieve_script_dir = '/usr/local/apache/htdocs/SearchEngine/scripts/';
my $INDEX_dir = '/share3/text/WWW/tau060911';
my $PRINT_THRESHOLD = 1000;

# HTTP�إå�����
print header(-charset => 'euc-jp');

# ���ꤵ�줿�գң̤�ɽ��       
if ($URL) {

    my $color;
    my $html = `nkf -e $URL`;
    
    # ���ե�����Υإå��������뤿�ᡢ�ǽ�ζ��Ԥ������
    $html =~ s/^.*?\n\s*\n//s;

    # KEY���Ȥ˿����դ���
    my @KEYS = split(/:/, $cgi->param('KEYS'));   	
    print "<BR><U>�ʲ��Υ�����ɤ��ϥ��饤�Ȥ���Ƥ��ޤ�:";
    for my $key (@KEYS) {
	next unless ($key);
	print "<span style=\"background-color:#$COLOR[$color];\">$key</span>";
	$html =~ s/$key/<span style="background-color:#$COLOR[$color];">$key<\/span>/g;
	$color++;
    }
    print "</U><BR><BR>$html";
}

else {

    # HTMl����
    print << "END_OF_HTML";
    <html>
	<head>
	<title>Search Engine</title>
	<link rel="stylesheet" type="text/css" href="cf.css">
	</head>
	<body>
END_OF_HTML

    # �����ȥ����
    print h1('�������󥸥�');
    
    # �ե��������
    print 
	start_form,
	"����: ",
	textfield(-name => 'INPUT'),
	submit('����'),
	reset('�ꥻ�å�'),
	end_form,
	hr, "\n";
    
    # ���Ϥ����ä����
    if ($INPUT) {
	
	# ������¸
	open(OUT, ">> input.log");
	print OUT "$date $ENV{REMOTE_ADDR}\t$INPUT\n";
	close OUT;
	
	# ����
	my $result; 
	$result = `echo $INPUT | nkf -w | /share/usr/bin/perl -I $retrieve_script_dir/ $retrieve_script_dir/retrieve.pl -d $INDEX_dir`;
	
	# undef�ξ��Ϸ����Ǥ�ʬ�䤹��
	# (���ѹ�) Retrieve.pm����������
	if ($result =~ /No file was found/) {
	    my $juman = `echo $INPUT | /share/usr/bin/juman`;
	    $INPUT = "";
	    for (split(/\n/, $juman)) {
		$INPUT .= &GetData($_) . " ";
	    }
	    $INPUT =~ s/ $//;
	    $result = `echo $INPUT | nkf -w | /share/usr/bin/perl -I $retrieve_script_dir/ $retrieve_script_dir/retrieve.pl -d $INDEX_dir`;
	}
	
	# ���Ϸ�̤�ɽ��
	my $color;
	for my $key (split(/\s/, $INPUT)) {
	    next unless ($key);
	    print " <span style=\"background-color:#$COLOR[$color];\">$key</span>";
	    $color++;
	}
	print ": ";
	
	if ($result =~ /No file was found/) {
	    print "$result";
	}
# 	elsif (/undef/) {
# 	    print "$result";
# 	}
	else {
	    my $output;
	    my @tmp_ids = split (' ', $result);
	    my @ids;
	    for (my $i = 0; $i < @tmp_ids; $i += 2) { # skip freq
		push(@ids, $tmp_ids[$i]);
	    }

	    print $#ids + 1 . "�ĤΥե����뤬���Ĥ���ޤ���<BR>";
	    print "�ǽ��${PRINT_THRESHOLD}���ɽ�����ޤ�<BR>" if @ids > $PRINT_THRESHOLD;
	    my $count = 0;
	    for my $id (@ids) {
		my $url = sprintf("INDEX/%02d/h%04d/%08d.html", $id / 1000000, $id / 10000, $id);
		$id = sprintf("%08d", $id);
		$INPUT =~ s/\s/:/g;
		$INPUT =~ s/��/:/g;
		$output .= "<a href=index.cgi?URL=$url&KEYS=" 
		    . &uri_escape($INPUT) . " target=\"_blank\" class=\"ex\">$id</a> ",
		$count++;
		last if $count >= $PRINT_THRESHOLD;
	    }
	    print $output;
	}
    }
    # �եå�����
    print << "END_OF_HTML";
    <hr>
	<address>&copy;2006 Kurohashi Lab.</address>
	</body>
	</html>
END_OF_HTML
}    

# �������Ѥ����Τߤ��֤�
sub GetData
{
    my ($input) = @_;
    return if ($input =~ /^(\<|\@|EOS)/);
    chomp $input;

    my @w = split(/\s+/, $input);

    # ���������
    return if ($w[2] =~ /^[\s*��]*$/);
    return if ($w[3] eq "����");
    return if ($w[5] =~ /^(��|��)��$/);
    return if ($w[5] =~ /^����$/);
    return if ($w[5] =~ /^(����|����Ū)̾��$/);

    return $w[2];
}
