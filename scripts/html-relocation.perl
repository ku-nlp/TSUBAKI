#!/usr/bin/env perl

# indirからfindしたHTMLファイルを対象に、10桁IDのファイル名にコピーし、1ディレクトリ10000個(default)ずつ格納する
# マッピング(outdir/filename2sid)を出力
# -d : dryrun
# -v : verbose
# -e html|html.gz : specify extention (default: html)
# -s start_dir_id : specify beginning dir id (default: 0)
# -n num_of_htmls_in_dir : specify # of htmls in a dir (default: 10000)

# Output:
# outdir/0000/000000/0000000000.html
# outdir/0000/000000/0000000001.html
# ：
# outdir/0000/000000/0000009999.html
# outdir/0000/000001/0000000000.html
# outdir/0000/000001/0000000001.html
# ：

use File::Find;
use File::Copy;
use File::Spec;
use File::Path;
use POSIX;
use Getopt::Long;
use strict;
use warnings;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

sub usage {
    print "Usage: $0 [--ext file_extention] [--dryrun] [--copy] [--verbose] [--start start_dir_id] [--num num_of_htmls_in_dir] indir ourdir\n";
    exit 1;
}

our %opt;
&GetOptions(\%opt, 'dryrun', 'ext=s', 'start=i', 'num=i', 'copy', 'verbose', 'zip', 'input_is_zip', 'zip_tmp_dir=s');

if (@ARGV != 2 || ! -d $ARGV[0]) {
    &usage();
}

our $SRC_DIR = $ARGV[0];
our $DEST_DIR = $ARGV[1];
our $BASE_DIR = Cwd::getcwd(); # current directory
our $HTML_EXT = $opt{ext} ? $opt{ext} : 'html';
our $FILENAME2SID_NAME = 'filename2sid';
our $NUM_OF_HTMLS_IN_DIR = $opt{num} ? $opt{num} : 10000;
our $DIGIT_OF_LOWEST_HTML_FILE = int(log($NUM_OF_HTMLS_IN_DIR + 1) / log(10));
our $DIGIT_OF_LOWEST_DIR = 10 - $DIGIT_OF_LOWEST_HTML_FILE;

our $hcount = 0;
our $dcount = $opt{start} ? $opt{start} : 0;
our $dstr = sprintf("%0${DIGIT_OF_LOWEST_DIR}d", $dcount);
our $dstr4 = substr($dstr, 0, 4);
our $outdir = "$DEST_DIR/$dstr4/$dstr";
our ($outzip, $zip);
if ($opt{zip} && !$opt{input_is_zip}) {
    $outzip = "$DEST_DIR/$dstr4/$dstr.zip";
    $zip = Archive::Zip->new();
}

if ($opt{zip} || $opt{input_is_zip}) {
    $ENV{'TMPDIR'} = $opt{zip_tmp_dir};
}

unless ($opt{dryrun}) {
    &mkdir_outdir();

    open(FILENAME2SID, "> $DEST_DIR/$FILENAME2SID_NAME") or die "Cannot open $DEST_DIR/$FILENAME2SID_NAME\n";
}

if ($opt{input_is_zip}) {
    find({wanted => \&process_zip_file, follow => 1}, $SRC_DIR);
}
else {
    find({wanted => \&process_file, follow => 1}, $SRC_DIR);
}

unless ($opt{dryrun}) {
    close(FILENAME2SID);
}

sub process_zip_file {
    if (/([^\/]+\Q.zip\E)$/) {
	my $src_file = $File::Find::name;
	my $src_fullname = $File::Find::fullname;

	$dstr = sprintf("%0${DIGIT_OF_LOWEST_DIR}d", $dcount);
	$dstr4 = substr($dstr, 0, 4);
	$outzip = "$DEST_DIR/$dstr4/$dstr.zip";

	if ($dcount % 100 == 0) { 
	    &mkdir_outdir() unless $opt{dryrun};
	}

	copy($src_fullname, $outzip) or die "$! (copy: $src_fullname -> $outzip)";

	$zip = Archive::Zip->new();
	die "$! ($src_fullname)" unless $zip->read($outzip) == Archive::Zip::AZ_OK;

	$hcount = 0;
	my %filename2destid;
	my $over_num_flag = 0;
	foreach my $member ($zip->members()) {
	    my $filename = $member->fileName();
	    if ($filename =~ /$HTML_EXT$/) {
		if ($over_num_flag) {
		    $zip->removeMember($member);
		    next;
		}

		my $dest_id = $dstr . sprintf("%0${DIGIT_OF_LOWEST_HTML_FILE}d", $hcount);
		my $update_filename = "$dstr/$dest_id.$HTML_EXT";
		# update the filename
		$member->fileName($update_filename);
		$filename2destid{$filename} = $dest_id;

		$hcount++;
		if ($hcount > $NUM_OF_HTMLS_IN_DIR) {
		    print STDERR "Number of htmlfiles exceed $NUM_OF_HTMLS_IN_DIR\n";
		    $over_num_flag = 1;
		}
	    }
	    else {
		$zip->removeMember($member);
	    }
	}

	unless ( $zip->overwrite == AZ_OK ) {
	    print STDERR "write error ($outzip) -> skip\n";
	    unlink($outzip) or die "$!";
	}
	else {
	    for my $filename (sort {$filename2destid{$a} <=> $filename2destid{$b}} keys %filename2destid) {
		print FILENAME2SID "$filename $filename2destid{$filename}\n";
	    }
	    $dcount++;
	}
	undef $zip;
    }
}

sub process_file {
    if (/([^\/]+\Q.$HTML_EXT\E)$/) {
	my $src_basename = $1;
	my $src_file = $File::Find::name;
	my $src_fullname = $File::Find::fullname;

	if ($hcount >= $NUM_OF_HTMLS_IN_DIR) {
	    if ($opt{zip}) {
		unless ( $zip->writeToFileNamed($outzip) == AZ_OK ) {
		    die "write error ($outzip)\n";
		}
	    }

	    $dcount++;
	    $dstr = sprintf("%0${DIGIT_OF_LOWEST_DIR}d", $dcount);
	    $dstr4 = substr($dstr, 0, 4);
	    $outdir = "$DEST_DIR/$dstr4/$dstr";
	    if ($opt{zip}) {
		$outzip = "$DEST_DIR/$dstr4/$dstr.zip";
		$zip = Archive::Zip->new();
	    }
	    &mkdir_outdir() unless $opt{dryrun};
	    $hcount = 0;
	}

	my $dest_id = $dstr . sprintf("%0${DIGIT_OF_LOWEST_HTML_FILE}d", $hcount);
	my $dest_file = "$outdir/$dest_id.$HTML_EXT";
	my $dest_fullname = File::Spec->rel2abs($dest_file, $BASE_DIR);

	if ($opt{dryrun}) {
	    print "$src_fullname -> $dest_fullname\n";
	}
	else {
	    print "$src_fullname -> $dest_fullname\n" if $opt{verbose};
	    print FILENAME2SID "$src_basename $dest_id\n";
	    if ($opt{zip}) {
		if ($opt{copy}) {
		    $zip->addFile($src_fullname, "$dstr/$dest_id.$HTML_EXT");
		}
		else {
		    my $member = $zip->addString($src_fullname, "$dstr/$dest_id.$HTML_EXT");
		    $member->{'externalFileAttributes'} = 0xA1FF0000;
		}
	    }
	    else {
		if ($opt{copy}) {
		    copy($src_fullname, $dest_fullname) or die "$! (copy: $src_fullname -> $dest_fullname)";
		}
		else {
		    symlink($src_fullname, $dest_fullname) or die "$! (symlink: $src_fullname -> $dest_fullname)";
		}
	    }
	}

	$hcount++;
    }
}

if ($opt{zip} && !$opt{input_is_zip}) {
    unless ( $zip->writeToFileNamed($outzip) == AZ_OK ) {
	die "write error ($outzip)\n";
    }
}

sub mkdir_outdir {
    if (! -d $outdir) {
	if (! -d "$DEST_DIR/$dstr4") {
	    if (! -d $DEST_DIR) {
		mkdir $DEST_DIR;
	    }
	    mkdir "$DEST_DIR/$dstr4";
	}
	mkdir "$outdir" unless $opt{zip} || $opt{input_is_zip};
    }
}
