package StandardFormatData;

# $Id$

use strict;
use utf8;

sub new {
    my ($class, $fp, $opt) = @_;

    my ($did) = ($fp =~ /(\d+)\.xml/);
    if ($opt->{gzipped}) {
	open(READER, "zcat | $fp") or die;
    } else {
	open(READER, $fp) or die;
    }
    binmode(READER, ':utf8');

    my $buf;
    while (<READER>) {
	$buf .= $_;
    }
    close(READER);

    my $this = {did => $did};
    &parse($this, $buf);

    bless $this;
}

sub DESTROY {}

sub parse {
    my ($this, $xmldat) = @_;

    ($this->{url}, $this->{encoding}, $this->{time}) = ($xmldat =~ /Url="(.+?)" OriginalEncoding="(.+?)" Time="(.+?)"/);

    my ($header) = ($xmldat =~ m!<Header>((.|\n)+?)</Header>!);
    my ($text) = ($xmldat =~ m!<Text[^>]+?>((.|\n)+?)</Text>!);

    $this->{title} = &parseMetaInfo($header, "Title");
    $this->{keywords} = &parseMetaInfo($header, "Keywords");
    $this->{description} = &parseMetaInfo($header, "Description");

    $this->{outlinks} = &parseLinkInfo($header, "OutLink");
    $this->{inlinks} = &parseLinkInfo($header, "InLink");

    $this->{sentences} = &parseText($text);
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
    my ($annotation) = @_;

    my @buf = split("\n", $annotation);
    shift @buf;
    my $hoge = pop @buf;

    return join("\n", @buf);
}

sub parseText {
    my ($text) = @_;

    my @sentences;
    while ($text =~ m!<S[^>]+?>((.|\n)+)</S>!g) {
	my $sentence = $1;
	my ($rawstring) = ($sentence =~ m!<RawString>(.+?)</RawString>!);
	my ($annotation) = ($sentence =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	push(@sentences, { rawstring => $rawstring, annotation => &trim($annotation) });
    }

    return \@sentences;
}

sub parseMetaInfo {
    my ($header, $tagname) = @_;

    my $item;
    if ($header =~ m!<$tagname[^>]*?>((.|\n)+)</$tagname>!) {
	my $element = $1;

	my ($rawstring) = ($element =~ m!<RawString>(.+?)</RawString>!);
	my ($annotation) = ($element =~ m!<Annotation[^>]+>((.|\n)+?)</Annotation>!);

	$item->{rawstring} = $rawstring;
	$item->{annotation} = &trim($annotation);
    }

    return $item;
}

sub parseLinkInfo {
    my ($header, $tagname) = @_;

    my @links;
    while ($header =~ m!<$tagname>((.|\n)+)</$tagname>!g) {
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
		       annotation => &trim($annotation),
		       urls => \@urls,
		       dids => \@dids });
    }

    return \@links;
}


# 	if (/\<$opt{extract_from}( |\>)/) {
# 	    $contentFlag = 1;
# 	}
# 	elsif (/\<\/$opt{extract_from}\>/) {
# 	    $contentFlag = 0;
# 	}

# 	if (/\<S.*? Id="(\d+)"/) {
# 	    print STDERR "\rdir=$opt{in},file=$fid (Id=$1)" if ($opt{verbose});
# 	    $sid = $1;
# 	}
# 	elsif (/\<(?:Title|InLink|OutLink|Description|Keywords)/) {
# 	    $sid++;
# 	    print STDERR "\rdir=$opt{in},file=$fid (Id=$sid)" if ($opt{verbose});
# 	}


# 	if (/^\]\]\><\/Annotation>/) {
# 	    unless ($result =~ /^\n*$/) {
# 		if ($opt{syn}) {
# 		    $indice{$sid} = $indexer->makeIndexfromSynGraph4Indexing($result);
# 		}
# 		elsif ($opt{knp}) {
# 		    $indice{$sid} = $indexer->makeIndexFromKNPResult($result, \%opt);
# 		}
# 		else {
# 		    $indice{$sid} = $indexer->makeIndexfromJumanResult($result);
# 		}
# 	    }

# 	    $result = undef;
# 	    $annotationFlag = 0;
# 	} elsif (/.*\<Annotation Scheme=\"$opt{scheme}\"\>\<\!\[CDATA\[/) {
# 	    my $line = "$'";
# 	    $result = $line unless ($line =~ /^#/);
# 	    $annotationFlag = 1;
# 	} elsif ($annotationFlag && $contentFlag) {
# 	    next if ($_ =~ /^\#/);

# 	    if ($opt{scheme} eq 'SynGraph' && $opt{knp}) {
# 		next if ($_ =~ /^!/);
# 	    }
# 	    $result .= $_;
# 	}
#     }

1;
