#!/usr/bin/env perl

# $Id$

###################################################
# 単語頻度の計数結果をマージ (全てをメモリ上に保持)
###################################################

use strict;
use utf8;
use Getopt::Long;
use Encode;

my (%opt); GetOptions(\%opt, 'dir=s', 'idxfiles=s', 'suffix=s', 'n=s', 'z', 'compress', 'verbose', 'offset=s', 'idx2did=s', 'ignore_version');

# 単語IDの初期化
my %freq;
my $fcnt = 0;

$opt{suffix} = 'idx' unless $opt{suffix};

# ディレクトリが指定された場合
if ($opt{dir} && !$opt{idxfiles}) {

    # データのあるディレクトリを開く
    opendir (DIR, $opt{dir}) or die;

    foreach my $file (sort {$a <=> $b} readdir(DIR)) {
	# .idxファイルが対象
	if($opt{z}){
	    next if($file !~ /.+\.$opt{suffix}\.gz$/);
	}else{
	    next if ($file !~ /.+\.$opt{suffix}$/);
	}

	print STDERR "\r($fcnt)" if($fcnt%113 == 0 && $opt{verbose});
	$fcnt++;

	# ファイルから読み込む
	if ($opt{z}) {
	    open (FILE, "zcat $opt{dir}/$file |") or die("no such file $file\n");
	    binmode(FILE, ':utf8');
	} else {
	    open (FILE, '<:utf8', "$opt{dir}/$file") or die("no such file $file\n");
	}
	while (<FILE>) {
	    &ReadData($_);
	}
	close FILE;

	if (defined($opt{n})) {
	    if ($fcnt % $opt{n} == 0) {
		my $fname = sprintf("$opt{dir}.%d.%d.%s", $fcnt/$opt{n}, $$, $opt{suffix});
		&output_data($fname, \%freq);
		%freq = ();
	    }
	}
    }
    closedir(DIR);
}
# .idxファイルのリストが与えられた場合
elsif ($opt{idxfiles}) {

    my $sid2tid = undef;
    if ($opt{idx2did}) {
	# .idx ファイルに id を振る
	$sid2tid = ();
	open (FILE, $opt{idx2did}) or die "$!";
	while (<FILE>) {
	    chop;
	    my ($sid, $tid) = split (/ /, $_);

	    $sid =~ s/\-\d+$// if ($opt{ignore_version});
	    $sid2tid->{$sid} = $tid;
	}
	close (FILE);
    }

    open (FILE, $opt{idxfiles}) or die "$!";
    while (<FILE>) {
	chop;

	my $file = $_;
	# ファイルから読み込む
	if ($opt{z}) {
	    open (IDX_FILE, "zcat $file |") or die("no such file $file\n");
	    binmode(IDX_FILE, ':utf8');
	} else {
	    open (IDX_FILE, '<:utf8', "$file") or die("no such file $file\n");
	}
	$fcnt++;

	while (<IDX_FILE>) {
	    &ReadData($_, $sid2tid);
	}
	close IDX_FILE;

	if (defined($opt{n})) {
	    if ($fcnt % $opt{n} == 0) {
		my $fname = sprintf("%s.%d.%d.%s", $opt{idxfiles}, $fcnt/$opt{n}, $$, $opt{suffix});
		&output_data($fname, \%freq);
		%freq = ();
	    }
	}
    }
    close (FILE);

    $opt{dir} = $opt{idxfiles};

}
# ディレクトリの指定がない場合は標準入力から読む
else {
    while (<STDIN>) {
	&ReadData($_);
    }
}

print STDERR "\r($fcnt) done.\n";

if (defined($opt{n})) {
    my $size = scalar(keys %freq);
    if ($size > 0) {
	my $fname = sprintf("$opt{dir}.%d.%d.%s", 1 + $fcnt/$opt{n}, $$, $opt{suffix});
	&output_data($fname, \%freq);
    }
}else{
    # 標準出力に出力
    foreach my $midashi (sort {$a cmp $b} keys %freq) {
	my $midashi_utf8 = encode('utf8', $midashi);
	print "$midashi_utf8";
	foreach my $did (sort {$a <=> $b} keys %{$freq{$midashi}}) {
	    print " $freq{$midashi}->{$did}";
	}
	print "\n";
    }
}

sub output_data {
    my ($fname, $freq) = @_;

    if ($opt{compress}) {
	$fname .= ".gz";
	open(WRITER, "| gzip > $fname");
    } else {
	open(WRITER, "> $fname");
    }
    binmode(WRITER, ':utf8');

    foreach my $midashi (sort {$a cmp $b} keys %$freq) {
	print WRITER "$midashi";
	foreach my $did (sort {$a <=> $b} keys %{$freq->{$midashi}}) {
	    print WRITER " $freq->{$midashi}->{$did}";
	}
	print WRITER "\n";
    }
    close(WRITER);
}

# データを読んで、各単語が出現するDocumentIDをマージ
sub ReadData
{
    my ($input, $sid2tid) = @_;
    chomp $input;

    my ($midashi, $etc) = split(/\s+/, $input);
    my ($sid, $dinfo) = split(':', $etc);
#   $sid =~ s/.link//;

    # sid を変更
    if (defined $sid2tid) {
	my $buf = $sid;
	$sid = $sid2tid->{$sid};
	$etc = $sid . ":" . $dinfo;
	print STDERR "[WARNING] $buf does not have an internal ID!\n" unless (defined $sid);
    }

    # 各単語IDの頻度を計数
    $freq{$midashi}->{$sid} = $etc;
}
