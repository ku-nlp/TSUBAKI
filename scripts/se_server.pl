#!/usr/bin/env perl

use strict;
use IO::Socket;
use Retrieve;
use Encode;
use URI::Escape;

my $port = 9686; # �ݡ����ֹ������
# my $JUMAN_HOME = "/share/tool/juman/bin";
my $JUMAN_HOME = "/home/skeiji/local/bin";
my $listening_socket = IO::Socket::INET->new(LocalPort => $port,
					     Listen    => SOMAXCONN,
					     Proto     => 'tcp',
					     Reuse     => 1,
					     );

unless($listening_socket){
    die "listen �Ǥ��ޤ���Ǥ����� $!\n";
}

my $INDEX_dir = $ARGV[0];
my $PRINT_THRESHOLD = 50;
my $retrieve = new Retrieve($INDEX_dir);

# print "�ݡ��� $port ��ĥ��ޤ���\n";

while(1){
    my $new_socket = $listening_socket->accept();

    my $client_sockaddr = $new_socket->peername();
    my ($client_port,$client_iaddr) = unpack_sockaddr_in($client_sockaddr);
    my $client_hostname = gethostbyaddr($client_iaddr, AF_INET);
    my $client_ip = inet_ntoa($client_iaddr);

#    print "��³: $client_hostname($client_ip) �ݡ��� $client_port\n";

    select($new_socket); $|=1; select(STDOUT);

    my $search_q = "";
    while($search_q = <$new_socket>){
	chomp($search_q);
	my($input,$ranking_method,$logical_cond) = split(/,/,$search_q);
	# ����
#	$input = "����";
	my @result = $retrieve->search(decode('euc-jp',$input),$ranking_method,$logical_cond);

	# undef�ξ��Ϸ����Ǥ�ʬ�䤹��
	# (���ѹ�) Retrieve.pm����������
	unless (@result) {
	    my $juman = `echo "$input" | $JUMAN_HOME/juman`;
	    $input = "";
	    for (split(/\n/, $juman)) {
		next if ($_ =~ /^(\<|\@|EOS)/);
		$input .= &GetData($_) . " ";
	    }
	    $input =~ s/ $//;
	    print "now retrieving the keyword(s) ($input)\n";
	    @result = $retrieve->search(decode('euc-jp',$input),$ranking_method,$logical_cond);
	}

	unless(@result){
	    print $new_socket "0\n";
	    print $new_socket "No file was found\n";
	}else{
	    my $output;
	    my $count = 0;
	    foreach (@result){
		my $id = $_->{did};
		my $score = $_->{score};
		$output .= "$id,$score\[RET\]";

#		my $url = sprintf("INDEX/%02d/h%04d/%08d.html", $id / 1000000, $id / 10000, $id);
#		$id = sprintf("%08d", $id);
#		$input =~ s/\s/:/g;
#		$input =~ s/��/:/g;
#		$output .= "<a href=index.cgi?URL=$url&KEYS=" . &uri_escape($input) . " target=\"_blank\" class=\"ex\">$id<sub>$score</sub></a>[RET]",
		$count++;
#		last if($count >= $PRINT_THRESHOLD);
	    }
	    my $size = scalar(@result);
	    print $new_socket "$size\n";
	    print $new_socket "$output\n";
	}
#	print $new_socket $;
    }
    $new_socket->close();

#   print "��³���ڤ�ޤ���������³���ݡ��� $port ��ĥ��ޤ���\n";
}


# �������Ѥ����Τߤ��֤�
sub GetData
{
    my ($input) = @_;
#   return if ($input =~ /^(\<|\@|EOS)/);
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
