## convert .medie-input.so into tsubaki standard format

package Medie2Tsubaki;

use strict;

sub convert_sentence {
    my @sentence = @_;
    my %head_table = ();    # phrase ID -> lexhead ID
    my %arg_table = ();     # word span -> arguments (hash of (arglabel, argID))
    my %phrase_table = ();  # phrase span -> phrase ID
    my %word_table = ();    # word ID -> word span
    ## collect word/phrase information
    foreach my $line (@sentence) {
        my($start, $end, $tag, $attr) = @$line;
        if ($tag eq "phrase") {
            $attr =~ /id=\"(.*?)\".*lex_head=\"(.*?)\"/;
            $head_table{$1} = $2;
            $phrase_table{"$start/$end"} = $1;
        } elsif ($tag eq "word") {
            my($id, $pred) = $attr =~ /id=\"(.*?)\".*pred=\"(.*?)\"/;
            my %args = $attr =~ /(arg.)=\"(.*?)\"/g;
            $arg_table{"$start/$end"} = \%args;
            $word_table{$id} = "$start/$end";
        }
    }
    ## map word ID to preterimnal ID
    while (my($phrase_id, $lexhead_id) = each %head_table) {
        $head_table{$phrase_id} = $phrase_table{$word_table{$lexhead_id}};
    }
    ## convert phrase/word tags
    my @converted = ();
    foreach my $line (@sentence) {
        my($start, $end, $tag, $attr) = @$line;
        if ($tag eq "sentence") {
            push @converted, [$start, $end, "Annotation", "tool=\"MEDIE tools\" score=\"1.0\""];
            #push @converted, [$start, $end, "result", "score=\"1.0\""];  ## deprecated
        } elsif ($tag eq "phrase") {
            next if $attr =~ /schema=/;  ## use only preterminals
            my @labels = ();
            my @args = ();
            while (my($label, $arg) = each %{$arg_table{"$start/$end"}}) {
                next if $arg eq "unk";
                push @labels, $label;
                push @args, $head_table{$arg};
            }
            my $args = @labels ? "dpndtype=\"" . join('/', @labels) . "\" head=\"" . join('/', @args) . "\"" : "";
            $attr =~ /id=\"(.*?)\".*cat=\"(.*?)\".*xcat=\"(.*?).*/;
            push @converted, [$start, $end, "phrase", "id=\"$1\" category=\"" . join('-', ($2, split /\s+/, $3)) . "\" feature=\"\" $args"];
        } elsif ($tag eq "word") {
            $attr =~ /id=\"(.*?)\".*pos=\"(.*?)\".*base=\"(.*?)\"/;
            push @converted, [$start, $end, "word", "id=\"$1\" lem=\"$3\" read=\"$3\" pos=\"$2\" repname=\"$3\" conj=\"\" feature=\"\""];
#         } elsif ($tag eq "entity_name") {
#             if ($attr =~ /facta_id=\"(.*?)\"/) {
#                 push @converted, [$start, $end, "synnode", "synid=\"$1\" score=\"0.99\""];
#             } elsif ($attr =~ /gena_id=\"(.*?)\"/) {
#                 push @converted, [$start, $end, "synnode", "synid=\"$1\" score=\"0.99\""];
#             }
        } elsif ($tag eq "sentence_type" || $tag eq "entity_name" || $tag eq "event_expression") {
            # ignore
        } else {
            die "Unknown tag: $start\t$end\t$tag\t$attr\n";
        }
    }
    return @converted;
}

1;

