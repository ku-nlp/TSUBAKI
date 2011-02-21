## remove unnecessary text from input and add <RawString>
## input: *-tsubaki1-*.xml.gz
## output: *-tsubaki-*.xml.gz

use strict;
use XML::LibXML;

my $XML_PARSER = XML::LibXML->new;

# if (@ARGV != 2) {
#     print STDERR "Usage: $0 input_xml output_xml\n";
#     exit 1;
# }

# my $input_xml = shift;
# my $output_xml = shift;

# open INPUT_XML, "gzip -dc < $input_xml |" or die "Cannot find file: $input_xml\n";
# my @input = <INPUT_XML>;
# close INPUT_XML;

my @input = <>;

my $xml = $XML_PARSER->parse_string(join('', @input));

## remove unnecessary text (text immediately under the top element)
my @nodes = $xml->findnodes("//StandardFormat");
foreach my $node (@nodes) {
    foreach my $child ($node->childNodes) {
        if ($child->nodeType == XML_TEXT_NODE) {
            $node->removeChild($child);
        }
    }
}

## add "RawString" tag
my @nodes = ($xml->findnodes("//Title"), $xml->findnodes("//S"));
foreach my $node (@nodes) {
    my $text = join('', map { $_->toString; } $node->findnodes(".//text()"));
    my $newnode = $xml->createElement("RawString");
    $newnode->appendText($text);
    $node->appendChild($newnode);
}

## move surface string to "str" tag
my @nodes = $xml->findnodes("//word");
foreach my $node (@nodes) {
    my $text_node = $node->firstChild;
    $node->setAttribute("str", $text_node->toString);
    $node->removeChild($text_node);
}

# open OUTPUT_XML, "| gzip -c > $output_xml" or die "Cannot open file: $output_xml\n";
# print OUTPUT_XML $xml->toString;
# close OUTPUT_XML;

print $xml->toString;

