## convert XML format of Enju to TSUBAKI standard format

use strict;
use Medie2Tsubaki;

sub convert {
    if (@_) {
        my @converted = &Medie2Tsubaki::convert_sentence(@_);
        map { print join("\t", @$_), "\n" } @converted;
    }
}

my @tags = ();
while (<>) {
    my($start, $end, $tag, $attrs) = /^(\d+)\s+(\d+)\s+(\S+)\s*(.*)$/;
    if ($tag eq "sentence") {
        &convert(@tags);
        @tags = ();
        $attrs =~ /id=\"(.*?)\"/;
        print join("\t", $start, $end, "S", "id=\"$1\""), "\n";
    } elsif ($tag eq "cons") {
        push @tags, [$start, $end, "phrase", $attrs];
    } elsif ($tag eq "tok") {
        push @tags, [$start, $end, "word", $attrs];
    }
}

&convert(@tags);

