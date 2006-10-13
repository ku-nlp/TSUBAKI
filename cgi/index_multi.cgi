#!/share/usr/bin/perl

use strict;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;
use Retrieve;
use Encode;

use IO::Socket;
use IO::Select;

my $cgi = new CGI;
my $URL = $cgi->param('URL');
my $INPUT = $cgi->param('INPUT');
my $RANKING_METHOD = $cgi->param('rank');
my $date = `date +%m%d-%H%M%S`;
chomp ($date);

my @COLOR = ("ffff66", "a0ffff", "99ff99", "ff9999", "ff66ff", 
	     "880000", "00aa00", "886800", "004699", "990099");


my $retrieve_script_dir = '/usr/local/apache/htdocs/SearchEngine/scripts/';
my $INDEX_dir = '/share3/text/WWW/tau060911';
my $PRINT_THRESHOLD = 1000;

unless(@ARGV){
    for(my $i = 1; $i < 24; $i++){
	if($i > 9){
	    push(@ARGV, "nlpc$i");
	}else{
	    push(@ARGV, "nlpc0$i");
	}
    }
}

#my @hosts = @ARGV;
my $port = 9684;

#my $retrieve = new Retrieve($INDEX_dir);

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
	
	my $hitcount = 0;
	my $doclinks = "";
	my $selecter = IO::Select->new;

	# ����
	for(my $i = 0; $i < scalar(@hosts); $i++){
	    my $host = $hosts[$i];
#	    print "$host:$port ����³���ޤ���\n";
	    
	    my $socket = IO::Socket::INET->new(PeerAddr => $host,
					       PeerPort => $port,
					       Proto    => 'tcp',
					       );
	    $selecter->add($socket);
	    unless($socket){
		die "$host ����³�Ǥ��ޤ���Ǥ����� $!\n";
	    }
	    
	    # ʸ���������
#	    print "������å�����: $query\n";
	    print $socket "$INPUT,$RANKING_METHOD\n";
	    $socket->flush();
	}
	
	# ʸ��������
	my $num_of_sockets = scalar(@hosts);
	while($num_of_sockets > 0){
	    my($readable_sockets) = IO::Select->select($selecter, undef, undef, undef);
	    foreach my $socket (@{$readable_sockets}){
		my $buff = <$socket>;
		chop($buff);
		$hitcount += $buff;
		
		$buff = <$socket>;
		$buff =~ s/\[RET\]/\n/g;
		$doclinks .= "$buff<hr>\n";
#		print "������å�����:\n$buff";
		
		$selecter->remove($socket);
		$socket->close();
		$num_of_sockets--;
	    }
	}

	
	# ���Ϸ�̤�ɽ��
	my $color;
	for my $key (split(/\s/, $INPUT)) {
	    next unless ($key);
	    print " <span style=\"background-color:#$COLOR[$color];\">$key</span>";
	    $color++;
	}
	print ": ";

	if($hitcount < 1){
	    print "No file was found";
	}else{
	    my $output;
# 	    my @ids = map({$_->{did}} @result);

 	    print "$hitcount�ĤΥե����뤬���Ĥ���ޤ���<BR>";
# 	    print $#ids + 1 . "�ĤΥե����뤬���Ĥ���ޤ���<BR>";
 	    print "�ǽ��${PRINT_THRESHOLD}���ɽ�����ޤ�<BR>" if $hitcount > $PRINT_THRESHOLD;
# 	    my $count = 0;
# 	    for my $id (@ids) {
# 		my $url = sprintf("INDEX/%02d/h%04d/%08d.html", $id / 1000000, $id / 10000, $id);
# 		$id = sprintf("%08d", $id);
# 		$INPUT =~ s/\s/:/g;
# 		$INPUT =~ s/��/:/g;
# 		$output .= "<a href=index.cgi?URL=$url&KEYS=" 
# 		    . &uri_escape($INPUT) . " target=\"_blank\" class=\"ex\">$id</a> ",
# 		$count++;
# 		last if $count >= $PRINT_THRESHOLD;
# 	    }
#	    print $output;
	    print $doclinks;
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
