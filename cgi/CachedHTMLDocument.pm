package CachedHTMLDocument;

# $Id$

use strict;
use utf8;
use HTML::TokeParser;
use Configure;
use Encode;
use Unicode::Japanese;
use URI::Split qw(uri_split uri_join);
use Data::Dumper;

my $CONFIG = Configure::get_instance();
my %MONTH = qw(Jan 1 Feb 2 Mar 3 Apr 4 May 5 Jun 6 Jul 7 Aug 8 Sep 9 Oct 10 Nov 11 Dec 12);

sub new {
    my ($class, $query, $opts) = @_;

    my $filename = $opts->{file};
    my $READER;
    if ($filename =~ /\.gz$/) {
	open($READER, "gzip -dc $filename |");
    } elsif ($filename =~ /^(.*[0-9]+):([0-9]+):([0-9-]+)$/) {
	use IO::Socket;
	$READER = IO::Socket::INET->new(PeerAddr => $1, PeerPort => $2, Proto => 'tcp') or die "cannot connect:$1:$2 $!\n";
	printf $READER "html ".$3."\n";
	$READER->flush();
    } else {
	open($READER, $filename);
    }
#   binmode($READER, ':utf8');

    my $flag = -1;
    my $crawler_html = 0;
    my $buf;
    my $url;
    my $crawled_date;

    while (<$READER>) {
	if (!$buf && /^HTML (\S+)/) {
	    $url = $1;
	    $crawler_html = 1;
	}

	if (/^Date: (.+)$/) {
	    $crawled_date = &convertTimeFormat($1);
	}

	# ヘッダーが読み終わるまでバッファリングしない
	if (!$crawler_html || $flag > 0) {
	    $buf .= $_;
	} else {
	    if ($_ =~ /^(\x0D\x0A|\x0D|\x0A|\r)$/) {
		$flag = 1;
	    }
	}
    }
    close $READER;

    my $encoding;
    if ($CONFIG->{IS_NICT_MODE}) {
	$encoding = 'utf8';
	$buf = decode ('utf8', $buf);
	$buf =~ tr/\x00-\x09\x0b-\x1f\x7f-\x9f//d;
    } else {
	require HtmlGuessEncoding;
 	my $HtmlGuessEncoding = new HtmlGuessEncoding({language => 'japanese'});
 	$encoding = $HtmlGuessEncoding->ProcessEncoding(\$buf, {change_to_utf8_with_flag => 1});
    }

    require ModifiedTokeParser;
    my $parser = ModifiedTokeParser->new(\$buf) or die $!;

    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.cdb\n";

    my $color;
    my @patterns;
    my %already_printed = ();
    my $message;

    $message = qq(<DIV style="margin-bottom: 2em; padding:1em; background-color:white; color: black; text-align: center; border-bottom: 2px solid black;">);

    if ($url) {
	if ($crawled_date) {
	    $message .= qq(<A href="$url" style="color: blue;">$url</A> のキャッシュです。（$crawled_date に取得）<BR>);
	}
	else {
	    $message .= qq(<A href="$url" style="color: blue;">$url</A> のキャッシュです。<BR>);
	}
    }
    $message .= "</DIV>";

    if (!$CONFIG->{IS_NICT_MODE}) { # NICT以外ではmessageを表示
	$message = qq(<DIV style="margin-bottom: 2em; padding:1em; background-color:white; color: black; text-align: center; border-bottom: 2px solid black;">);

	if ($url) {
	    if ($crawled_date) {
		$message .= qq(<A href="$url" style="color: blue;">$url</A> のキャッシュです。（$crawled_date に取得）<BR>);
	    }
	    else {
		$message .= qq(<A href="$url" style="color: blue;">$url</A> のキャッシュです。<BR>);
	    }
	}

	$message .= "次の単語とその同義語がハイライトされています:&nbsp;";
    }

    foreach my $reps (split(/,/, $query)) {
	foreach my $word (split(/;/,  $reps)) {
	    next unless ($word);

	    if ($word =~ /^s\d+/) {
		foreach my $synonym (sort {length($b) <=> length($a)} split('\|', decode('utf8', $synonyms{$word}))) {
		    # 読みの削除
		    if ($synonym =~ m!^([^/]+)/!) {
			$synonym = $1;
		    }

		    # 情報源を削除
		    $synonym =~ s/\[.+?\]//;

		    $synonym =~ s/<[^>]+>//g;
		    push(@patterns, {key => $synonym, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$synonym<\/span>)});
		    my $h_synonym = Unicode::Japanese->new($synonym)->z2h->get;
		    push(@patterns, {key => $h_synonym, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$h_synonym<\/span>)});
		}
	    }
	    # 単語はヘッダーには表示
	    else {
		my @buff = ();
		foreach my $w (split (/\+/, $word)) {
		    # 読みの削除
		    $w = $1 if ($w =~ m!^([^/]+)/!);
		    push (@buff, $w);
		}
		$word = join ("", @buff);
		next if (exists $already_printed{$word});
		$already_printed{$word} = 1;

		if (!$CONFIG->{IS_NICT_MODE}) {
		    $message .= sprintf qq(<span style="background-color:#%s;">), $CONFIG->{HIGHLIGHT_COLOR}[$color];
		    $message .= sprintf qq(%s</span>&nbsp;), $word;
		}
		push(@patterns, {key => $word, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$word<\/span>)});

		my $h_word = Unicode::Japanese->new($word)->z2h->get;
		push(@patterns, {key => $h_word, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$h_word<\/span>)});
	    }
	}
	$color = (++$color%scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
    }
    $message .= "</DIV>" if !$CONFIG->{IS_NICT_MODE};

    @patterns = sort {length($b->{key}) <=> length($a->{key})} @patterns;


    my $header;
    my $buf;
    my $inBody = 0;
    # トークンを処理する
    while (my $token = $parser->get_token) {
        my $type = $token->[0];

	if ($type eq 'S') {
	    if ($token->[1] eq 'body') {
		# 背景画像のURLを取得
		my $fpath = $token->[2]{background};
 		if ($fpath) {
 		    my $furl = &convertURL($url, $fpath);
		    $token->[6] =~ s/\Q$fpath\E/$furl/;
		}

		$buf .= $token->[6];
		$inBody = 1;
	    }
	    else {
		if ($token->[1] eq 'meta' && $token->[6] =~ /charset/i) {
		    # 文字コードの指定がある場合は, コメントアウト
		    $buf .= ("<!-- " . $token->[6] . "-->\n");
		}
		else {
		    my $fpath;
		    my $tagname = $token->[1];
		    if ($tagname eq 'a' || $tagname eq 'link') {
			$fpath = $token->[2]{href};
		    }
		    elsif ($tagname eq 'img' || $tagname eq 'script') {
			$fpath = $token->[2]{src};
		    }
		    else {
			$fpath = $token->[2]{background};
		    }

		    # 相対パスを絶対パスに変換
		    if ($fpath) {
			my $furl = &convertURL($url, $fpath);
			$token->[6] =~ s/\Q$fpath\E/$furl/;
		    }

		    $buf .= $token->[6];
		}
	    }
        }
	elsif ($type eq 'E') {
            $buf .= $token->[2];
	}
	elsif ($type eq 'T') {
	    my $text = $token->[1];
	    if ($inBody) {
		foreach my $p (@patterns) {
		    if (index($text, $p->{key}) > -1) {
			my $k = $p->{key};
			my $r = $p->{regexp};
			$text =~ s/\Q$k\E/$r/ig;
		    }
		}
	    }
            $buf .= $text;
	}
	elsif ($type eq 'C') {
            $buf .= $token->[1];
	}
    }

    my $this = {
	FILE_PATH => $opts->{file},
	HEADER => $header,
	MESSAGE => $message,
	RAWDATA => $buf,
	BODY => $message . $buf,
	ENCODING => $encoding,
	CRAWLED_DATE => $crawled_date
    };

    bless $this;
}

sub getCrawledDate {
    my ($this) = @_;

    return $this->{CRAWLED_DATE};
}

sub convertTimeFormat {
    my ($t) = @_;

    my ($youbi, $day, $month, $year, $time, $gmt) = split (/ /, $t);
    my ($hour, $min, $sec) = split (/:/, $time);
    $hour += 9;

    if ($hour > 23) {
	$day++;
	$hour %= 24;
    }


    my $_month = $MONTH{$month};
    if (($day > 31 && $month =~ /Jan|Mar|May|Jul|Aug|Oct|Dec/) ||
	($day > 30 && $month =~ /Apr|Jun|Sep|Nov/)) {
	$day = 1;
	$_month++;
    }


    if ($_month > 12) {
	$year++;
	$_month = 1;
    }

    return sprintf ("%04d年%d月%d日 %d時%d分%d秒", $year,$_month, $day, $hour, $min, $sec);
}


sub convertTimeFormatFromGMT {
    my ($t) = @_;

    my ($date, $time, $gmt) = split (/ /, $t);
    my ($year, $month, $day) = split (/\-/, $date);
    my ($hour, $min, $sec) = split (/:/, $time);
    $hour += 9;

    if ($hour > 23) {
	$day++;
	$hour %= 24;
    }


    if (($day > 31 && $month =~ /01|03|05|07|08|10|12/) ||
	($day > 30 && $month =~ /04|07|09|11/)) {
	$day = 1;
	$month++;
    }

    if ($month > 12) {
	$year++;
	$month = 1;
    }

    return sprintf ("%04d年%d月%d日 %d時%d分%d秒", $year,$month, $day, $hour, $min, $sec);
}

sub DESTROY {
}

sub to_string {
    my ($this, $query, $opt) = @_;

    return $this->{BODY};
}

sub to_string_for_ipsj {
    my ($this, $query, $opt) = @_;

    my $rawdata = $this->{RAWDATA};
    $rawdata =~ s/\n\n/<P>/g;
    $rawdata =~ s/\n/<BR>/g;
    $rawdata =~ s/&nbsp;/ /g;
    return sprintf ("%s\n<DIV>%s</DIV>", $this->{MESSAGE}, $rawdata);
}


sub convertURL {
    my ($url, $fpath) = @_;

    return $fpath if ($fpath =~ /^http/);

    $url =~ s!/{2,}!/!;
    $url =~ s!:/!://!;
    my ($scheme, $auth, $path, $query, $frag) = uri_split($url);

    if ($fpath =~ m!^/!) {
	return uri_join($scheme, $auth, $fpath);
    }
    else {
	if ($path =~ /\//) {
	    if ($path ne '/') {
		my @f = split('/', $path);
		$f[-1] = $fpath;
		return uri_join($scheme, $auth, join('/', @f));
	    } else {
		return uri_join($scheme, $auth, $path . $fpath);
	    }
	}
	else {
	    return uri_join($scheme, $auth, $path);
	}
    }
}

1;
