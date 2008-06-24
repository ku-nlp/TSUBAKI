package CachedHTMLDocument;

use strict;
use utf8;
use HTML::TokeParser;
use Configure;
use Encode;
use HtmlGuessEncoding;
use ModifiedTokeParser;

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
	if (!$buf and /^HTML (\S+)/) {
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


    my $color;
    my @patterns;
    my $message = qq(<DIV style="margin-bottom: 2em; padding:1em; background-color:#e0e0e0; color: black;">次の単語がハイライトされています:&nbsp;);
    my @KEYS = split(/:/, $query);
    foreach my $key (@KEYS) {
	next unless ($key);

	$message .= sprintf qq(<span style="background-color:#%s;">), $CONFIG->{HIGHLIGHT_COLOR}[$color];
	$message .= sprintf qq(%s</span>&nbsp;), $key;

	push(@patterns, {key => $key, regexp => qq(<span style="color: black; background-color:#$CONFIG->{HIGHLIGHT_COLOR}[$color];">$key<\/span>)});
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
		$buf .= $message;
		$inBody = 1;
	    } else {
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
			$text =~ s/$k/$r/g;
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
	BODY => $buf,
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

1;
