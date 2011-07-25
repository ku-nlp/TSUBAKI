#!/usr/bin/env perl

# $Id$

#################################################################
# idxファイルをバイナリ化するプログラム(オフセット値も同時に保存)
#################################################################

# -----
# USAGE
# -----
#
# For create:
# For create:
# perl -I somewhere/Utils/perl binarize_idx.pl -z -syn -quiet somewhere/000.idx.gz
#
# For test:
# perl -I somewhere/Utils/perl binarize_idx.pl -test -term s605:教師 -keymapfile somewhere/offset000.word.conv.cdb.keymap -idxfile somewhere/idx000.word.dat.conv

use strict;
use utf8;
use Getopt::Long;
use Encode;

my (%opt);
GetOptions(\%opt,
	   'wordth=i',
	   'dpndth=i',
	   'wordpos',
	   'dpndpos',
	   'legacy_mode',
	   'cdbdir=s',
	   'z',
	   'syn',
	   '32bit',
	   'test',
	   'keymapfile=s',
	   'idxfile=s',
	   'term=s',
	   'quiet',
	   'verbose'
	   );

# 足切りの閾値
my $wordth = $opt{wordth} ? $opt{wordth} : 0;
my $dpndth = $opt{dpndth} ? $opt{dpndth} : 0;

# 同義表現係り受けインデックス用に、索引として登録する係り受けのデータベースを読み込む
my @cdbs = ();
if ($opt{cdbdir}) {
    opendir(DIR, $opt{cdbdir});
    foreach my $f (sort {$a cmp $b} readdir(DIR)) {
	next unless ($f =~ /.dpnd.cdb.keymap/);

	# $f は登録されているキーのうち最も小さいキーとCDBファイルの対応が書かれたファイル
	# 例
	# % cat $f
	# s17699:ものを一つにする->s34274:買い物<尊敬> df.dpnd.cdb.1
	# s253:内部<反義語><否定>->s19414:ようすをしらべる<否定> df.dpnd.cdb.2
	# s3255:着く<可能>->s19215:賞<反義語><否定> df.dpnd.cdb.3
	# s720:漬かる<否定>->s26930:見られる<否定> df.dpnd.cdb.4
	# アイスブレーキング->探す df.dpnd.cdb.5
	# ...
	open(READER, '<:utf8', "$opt{cdbdir}/$f");
	while (<READER>) {
	    chop($_);
	    my ($k, $file) = split(/ /, $_);
	    my $dbfp = "$opt{cdbdir}/$file";
	    if (scalar(@cdbs) < 1) {
		my $new_dbfp = $dbfp;
		$new_dbfp =~ s/\d+$/0/;
		tie my %cdb, 'CDB_File', $new_dbfp or die "$0: can't tie to $new_dbfp $!\n";
		push(@cdbs, {key => '', cdb => \%cdb});
	    }
	    tie my %cdb, 'CDB_File', $dbfp or die "$0: can't tie to $dbfp $!\n";
	    push(@cdbs, {key => $k, cdb => \%cdb});
	}
	close(READER);
    }
    closedir(DIR);
}

if ($opt{test}) {
    &main4test();
} else {
    &main4create();
}

sub main4test {
    require CDB_Reader;


    my $FREQ_BIT_SIZE = 10;
    my $FREQ_MASK     = (2 ** $FREQ_BIT_SIZE) - 1;

    my $db = new CDB_Reader($opt{keymapfile});
    my $offset = $db->get(decode('utf8', $opt{term}));
    open (F, $opt{idxfile}) or die $!;

    # バイナリデータの読み込み
    my $buf;
    seek (F, $offset, 0);
    read (F, $buf, 4);
    my $datalen = unpack ("L", $buf);
    my $bindata;
    read (F, $bindata, $datalen);
    close (F);

    my $ldf = unpack ("L", substr($bindata, 0, 4));
    foreach my $i (0 .. $ldf - 1) {
	my $did    = unpack ("L", substr($bindata, 4 + $i * 4, 4));
	my $fbits  = unpack ("L", substr($bindata, 4 + $i * 4  +  4 * $ldf, 4));
	my $offset = unpack ("L", substr($bindata, 4 + $i * 4  +  8 * $ldf, 4));
	my $posnum = unpack ("L", substr($bindata, 4 + $offset + 12 * $ldf, 4));
	print "$did FEATURE=$fbits\t#POS=$posnum\t";
	my @buf;
	foreach my $j (0 .. $posnum - 1) {
	    my $feature = unpack ("L", substr($bindata, 12 * $ldf + 4 + $offset + 4 + $j * 8,     4));
	    my $posfreq = unpack ("L", substr($bindata, 12 * $ldf + 4 + $offset + 4 + $j * 8 + 4, 4));
	    my $freq = ($posfreq & $FREQ_MASK) / 1000;
	    my $pos = $posfreq >> $FREQ_BIT_SIZE;
	    push (@buf, sprintf ("f=%s,p=%s,s=%s", $feature, $pos, $freq));
	}
	print join (" ", @buf) . "\n";
    }
    print "LDF=$ldf\n";
}


sub main4create {
    require Binarizer;
    require SynGraphBinarizer;

    my $fp = $ARGV[0];
    unless ($fp =~ /(.*?)([^\/]+)\.(idx.*)$/) {
	die "file name is not *.idx ($fp)\n"
    } else {
	# 引数として*.idxファイルをとる
	my $DIR = $1;
	$DIR = '.' unless $DIR; # カレントディレクトリにあるファイルの場合、$DIRが空になるので、'.'を入れる
	my $NAME = $2;

	my $lcnt = 0;
	my $bins;
	if ($opt{syn}) {
	    my $idxf_w = ($opt{legacy_mode}) ? "${DIR}/idx$NAME.word.dat" : "${DIR}/idx$NAME.word.dat.conv";
	    my $idxf_d = ($opt{legacy_mode}) ? "${DIR}/idx$NAME.dpnd.dat" : "${DIR}/idx$NAME.dpnd.dat.conv";
	    my $offf_w = ($opt{legacy_mode}) ? "${DIR}/offset$NAME.word.cdb" : "${DIR}/offset$NAME.word.conv.cdb";
	    my $offf_d = ($opt{legacy_mode}) ? "${DIR}/offset$NAME.dpnd.cdb" : "${DIR}/offset$NAME.dpnd.conv.cdb";
	    $bins = {
		word => new SynGraphBinarizer($wordth, $idxf_w, $offf_w, 1, $opt{legacy_mode}, $opt{verbose}, $opt{'32bit'}),
		dpnd => new SynGraphBinarizer($dpndth, $idxf_d, $offf_d, 1, $opt{legacy_mode}, $opt{verbose}, $opt{'32bit'})
	    };
	} else {
	    $bins = {
		word => new Binarizer($wordth, "${DIR}/idx$NAME.word.dat", "${DIR}/offset$NAME.word.cdb", 1, $opt{verbose}),
		dpnd => new Binarizer($dpndth, "${DIR}/idx$NAME.dpnd.dat", "${DIR}/offset$NAME.dpnd.cdb", 1, $opt{verbose})
	    };
	}

	if ($opt{z}) {
	    open (READER, "zcat $fp |") || die "$!\n";
	} else {
	    open (READER, $fp) || die "$!\n";
	}

	while (<READER>) {
	    print STDERR "\rnow binarizing... ($lcnt)" if (!$opt{quiet} && ($lcnt%10) == 0);
	    $lcnt++;

	    chomp;
	    my ($index, @dlist) = split(' ', decode('utf8', $_));

	    my $bin = $bins->{word};
	    if (index($index, '->') > 0) {
		# 同義表現間の係り受け関係インデックスの場合は文書頻度データベースをひいて登録するか
		# どうかをチェックする（文書頻度データベースはあらかじめ足切りがされていること）
		if ($index =~ /s\d+/) {
		    if ($opt{cdbdir}) {
			my $cdb = $cdbs[-1]->{cdb};
			foreach my $e (@cdbs) {
			    if ($index gt $e->{key}) {
				$cdb = $e->{cdb};
			    } else {
				last;
			    }
			}

			my $df = $cdb->{$index};
			if ($df > 0) {
			    $bin = $bins->{dpnd};
			} else {
			    $bin = undef;
			}
		    }
		    else {
			$bin = $bins->{dpnd};
		    }
		} else {
		    $bin = $bins->{dpnd};
		}
	    }
	    $bin->add($index, \@dlist) if (defined $bin);
	}
	print STDERR "\rbinarizing ($lcnt) done.\n" if (!$opt{quiet});
	close(READER);

	$bins->{word}->close();
	$bins->{dpnd}->close();
    }
}

