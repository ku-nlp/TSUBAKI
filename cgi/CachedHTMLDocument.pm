package CachedHTMLDocument;

use strict;
use utf8;
use HTML::TokeParser;
use Configure;
use Encode;
use HtmlGuessEncoding;
use ModifiedTokeParser;
use Unicode::Japanese;
use URI::Split qw(uri_split uri_join);
use Data::Dumper;

my $CONFIG = Configure::get_instance();

sub new {
    my ($class, $query, $opts) = @_;

    my $filename = $opts->{file};
    if ($opts->{z}) {
	open(READER, "zcat $filename |");
    } else {
	open(READER, $filename);
    }

    my $flag = -1;
    my $crawler_html = 0;
    my $buf;
    my $url;

    while (<READER>) {
	if (!$buf && /^HTML (\S+)/) {
	    $url = $1;
	    $crawler_html = 1;
	}

	# ヘッダーが読み終わるまでバッファリングしない
	if (!$crawler_html || $flag > 0) {
	    $buf .= $_;
	} else {
	    if ($_ =~ /^\r$/) {
		$flag = 1;
	    }
	}
    }

    my $HtmlGuessEncoding = new HtmlGuessEncoding({language => 'japanese'});
    my $encoding = $HtmlGuessEncoding->ProcessEncoding(\$buf, {change_to_utf8_with_flag => 1});
    my $parser = ModifiedTokeParser->new(\$buf) or die $!;

    tie my %synonyms, 'CDB_File', "$CONFIG->{SYNDB_PATH}/syndb.mod.cdb" or die $! . " $CONFIG->{SYNDB_PATH}/syndb.mod.cdb\n";

    my $color;
    my @patterns;
    my $message = qq(<DIV style="margin-bottom: 2em; padding:1em; background-color:white; color: black; text-align: center; border-bottom: 2px solid black;">);
    $message .= qq(<A href="$url" style="color: blue;">$url</A> のキャッシュです。<BR>次の単語とその同義語がハイライトされています:&nbsp;);
    foreach my $reps (split(/,/, $query)) {
	foreach my $word (split(/;/,  $reps)) {
	    next unless ($word);

	    if ($word =~ /^s\d+/ || $word =~ /\+/) {
		foreach my $synonym (split('\|', decode('utf8', $synonyms{$word}))) {
		    # 読みの削除
		    if ($synonym =~ m!^([^/]+)/!) {
			$synonym = $1;
		    }

		    # 情報源を削除
		    $synonym =~ s/\[.+?\]//;

		    $word =~ s/\+//g;

		    $synonym =~ s/<[^>]+>//g;
		    push(@patterns, {key => $synonym, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$synonym<\/span>)});
		    my $h_synonym = Unicode::Japanese->new($synonym)->z2h->get;
		    push(@patterns, {key => $h_synonym, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$h_synonym<\/span>)});
		}
	    }
	    # 単語はヘッダーには表示
	    else {
		$message .= sprintf qq(<span style="background-color:#%s;">), $CONFIG->{HIGHLIGHT_COLOR}[$color];
		$message .= sprintf qq(%s</span>&nbsp;), $word;
		push(@patterns, {key => $word, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$word<\/span>)});
	    }
	}
	$color = (++$color%scalar(@{$CONFIG->{HIGHLIGHT_COLOR}}));
    }
    $message .= "</DIV>";


    my $header;
    my $buf;
    my $inBody = 0;
    # トークンを処理する
    while (my $token = $parser->get_token) {
        my $type = $token->[0];

	if ($type eq 'S') {
	    if ($token->[1] eq 'body') {
		$buf .= $token->[6];
		$inBody = 1;
	    }
	    elsif ($token->[1] =~ /(a|link|img)/) {
		my $fpath = ($1 eq 'link' || $1 eq 'a') ? $token->[2]{href} : $token->[2]{src};
 		if ($fpath) {
 		    my $furl = &convertURL($url, $fpath);
		    $token->[6] =~ s/\Q$fpath\E/$furl/;
 		}
		$buf .= $token->[6];
	    }
	    else {
		if ($token->[1] eq 'meta' && $token->[6] =~ /charset/i) {
		    # 文字コードの指定がある場合は, コメントアウト
		    $buf .= ("<!-- " . $token->[6] . "-->\n");
		} else {
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
	BODY => $message . $buf,
	ENCODING => $encoding
    };

    bless $this;
}

sub DESTROY {
}

sub to_string {
    my ($this, $query, $opt) = @_;

    return $this->{BODY};
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
	if ($path =~ /\// && $path ne '/') {
	    my @f = split('/', $path);
	    $f[-1] = $fpath;
	    return uri_join($scheme, $auth, join('/', @f));
	}
	else {
	    return uri_join($scheme, $auth, $path);
	}
    }
}

1;
