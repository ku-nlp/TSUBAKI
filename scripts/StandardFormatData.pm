package StandardFormatData;

# $Id$

use strict;
use utf8;

sub new {
    my ($class, $file, $opt) = @_;

    my $did;
    my $content;
    if ((ref $file) eq 'SCALAR') {
	$did = $opt->{did};
	$content = $$file;
    } else {
	($did) = ($file =~ /(\d+)\.xml/);
	if ($opt->{gzipped}) {
	    open(READER, "zcat $file |") or die "$!";
	} else {
	    open(READER, $file) or die "$!";
	}
	binmode(READER, ':utf8');

	while (<READER>) {
	    $content .= $_;
	}
	close(READER);
    }

    my $this = {did => $did, is_old_version => $opt->{is_old_version}};
    $this = bless $this;
    $this->parse($content);

    return $this;
}

sub DESTROY {}

sub parse {
    my ($this, $xmldat) = @_;

    ($this->{url}, $this->{encoding}, $this->{time}) = ($xmldat =~ /Url="(.+?)" OriginalEncoding="(.+?)" Time="(.+?)"/);

    my ($header) = ($xmldat =~ m!<Header>((.|\n)+?)</Header>!);
    my ($text) = ($xmldat =~ m!<Text[^>]+?>((.|\n)+?)</Text>!);

    $this->{title} = $this->parseMetaInfo($header, "Title");
    $this->{keywords} = $this->parseMetaInfo($header, "Keywords");
    $this->{description} = $this->parseMetaInfo($header, "Description");

    $this->{outlinks} = $this->parseLinkInfo($header, "OutLink");
    $this->{inlinks} = $this->parseLinkInfo($header, "InLink");

    $this->{sentences} = $this->parseText($text);
}

sub getID {
    my ($this) = @_;
    return $this->{id};
}

sub getInlinks {
    my ($this) = @_;
    return $this->{inlinks};
}

sub getOutlinks {
    my ($this) = @_;
    return $this->{outlinks};
}

sub getTitle {
    my ($this) = @_;
    return $this->{title};
}

sub getDescription {
    my ($this) = @_;
    return $this->{description};
}

sub getKeywords {
    my ($this) = @_;
    return $this->{keywords}
}

sub getUrl {
    my ($this) = @_;
    return $this->{url}
}

sub getEncoding {
    my ($this) = @_;
    return $this->{encoding}
}

sub getTime {
    my ($this) = @_;
    return $this->{time}
}

sub getSentences {
    my ($this) = @_;
    return $this->{sentences}
}


sub trim {
    my ($this, $annotation) = @_;

    $annotation =~ s/S\-ID:\d+//g;

    my @buf = split("\n", $annotation);
    if ($this->{is_old_version}) {
	my $line = shift @buf;
	$line =~ s/<!\[CDATA\[//;
	unshift(@buf, $line);
    } else {
	shift @buf;
    }
    pop @buf;

    return join("\n", @buf);
}

sub parseText {
    my ($this, $text) = @_;

    my @sentences;
    if ($this->{is_old_version}) {
	while ($text =~ m!<S[^>]+?Id="(\d+)".*?>((.|\n)+?</Annotation>)!g) {
	    my $sid = $1;
	    my $sentence = $2;
	    my ($rawstring) = ($sentence =~ m!<RawString>(.+?)</RawString>!);
	    my ($annotation) = ($sentence =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	    push(@sentences, { id => $sid, rawstring => $rawstring, annotation => $this->trim($annotation) });
	}
    } else {
	while ($text =~ m!<S[^>]+?Id="(\d+)".*?>((.|\n)+?)</S>!g) {
	    my $sid = $1;
	    my $sentence = $2;
	    my ($rawstring) = ($sentence =~ m!<RawString>(.+?)</RawString>!);
	    my ($annotation) = ($sentence =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	    push(@sentences, { id => $sid, rawstring => $rawstring, annotation => $this->trim($annotation) });
	}
    }

    return \@sentences;
}

sub parseMetaInfo {
    my ($this, $header, $tagname) = @_;

    my $item;
    my $element;
    if ($header =~ m!<$tagname[^>]*?>((.|\n)+?)</<$tagname>!) {
	$element = $1;
    }
    elsif ($header =~ m!<$tagname[^>]*?>((.|\n)+)! && $this->{is_old_version}) {
	$element = $1;
    }

    if ($element) {
	my ($rawstring) = ($element =~ m!<RawString>(.+?)</RawString>!);
	my ($annotation) = ($element =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	$item->{rawstring} = $rawstring;
	$item->{annotation} = $this->trim($annotation);
    }

    return $item;
}

sub parseLinkInfo {
    my ($this, $header, $tagname) = @_;

    my @links;
    while ($header =~ m!<$tagname>((.|\n)+?)</$tagname>!g) {
	my $link = $1;
	my ($rawstring) = ($link =~ m!<RawString>(.+?)</RawString>!);
	my ($annotation) = ($link =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	my @urls;
	my @dids;
	while ($link =~ m!<DocID Url="(.+?)">(.+?)</DocID>!g) {
	    push(@urls, $1);
	    push(@dids, $2);
	}

	push(@links, { rawstring => $rawstring,
		       annotation => $this->trim($annotation),
		       urls => \@urls,
		       dids => \@dids });
    }

    return \@links;
}

1;
