#!/usr/bin/env perl

use strict;
use utf8;
use Getopt::Long;
use CDB_File;

# binmode (STDIN,  ':encoding(euc-jp)');
# binmode (STDOUT, ':encoding(euc-jp)');
binmode (STDIN,  ':utf8');
binmode (STDOUT, ':utf8');

my (%opt);
GetOptions(\%opt, 'freq=s', 'number', 'katakana', 'alphabet', 'symbol', 'termdb=s');

$opt{freq} = 3 unless ($opt{freq});

sub kakko {
    return <<END;
3008\t3011
3014\t301B
FF08\tFF09
FF3B\tFF3B
FF3D\tFF3D
FF5B\tFF5B
FF5D\tFF5D
END
}

tie my %termdb, 'CDB_File', $opt{termdb} or die "$!\n" if ($opt{termdb});

while (<STDIN>) {
    my ($term, $freq) = split (/ /, $_);

    $term =~ s/\*$//;

    if ($term =~ /\-\>/) {
	my ($moto, $saki) = split (/\->/, $term);
	if ($freq > $opt{freq} && $termdb{$saki} && $termdb{$moto}) {
	    print $_;
	}
    } else {
	my $flag = 1;
	# 文書頻度が3以下のタームは削除
	$flag = 0 if ($freq <= $opt{freq});

	# 4文字以上の数字列かつ文書頻度が100000未満のものはインデックスから削除
	$flag = 0 if ($opt{number} && &isUnnecesaryNumberTerm ($term, $freq));

	# カタカナが20字以上連続した表現かつ文書頻度が10000以下のものは削除
	$flag = 0 if ($opt{katakana} && $freq <= 10000 && &isLongKatakana ($term));

	# 英単語10語以上の連続もしくは15文字以上のアルファベットの連続は削除
	$flag = 0 if ($opt{alphabet} && (&isAlphabetSequence ($term) || &isLongAlphabet ($term)));

	# 2文字以上で漢字、ひらがな、カタカナ、英数字、−、．の割合が5割未満のタームは削除
	$flag = 0 if ($opt{symbol} && &isSymbol ($term));

	if ($flag) {
	    print $_;
	}
    }
}

sub isSymbol {
    my ($term) = @_;

    if (length($term) > 2 && $term !~ /\+/ && $term !~ /s\d+/ && $term !~ />/) {
	my $j = 0;
	my $total = 0;
	foreach my $ch (split (//, $term)) {
	    $j++ if ($ch =~ /(\p{Han}|\p{Katakana}|\p{Hiragana}|\p{Latin}|\p{Number}|ー|．)/);
	    $total++;
	}
	if ($j / $total > 0.5) {
	    return 0;
	} else {
	    return 1;
	}
    } else {
	return 0;
    }
}

sub isUnnecesaryNumberTerm {
    my ($term, $freq) = @_;

    return 0 if ($term =~ /s\d+/);

    if ($term =~ /^(\p{Number}|．|　)+$/ && $freq < 100000) {
	if (length($&) <= 4) {
	    return 0;
	} else {
	    return 1;
	}
    } else {
	return 0;
    }
}

sub isSymbolSequence {
    my ($term) = @_;

    return 0 if ($term =~ /\+|\</);
    return 0 if ($term =~ /^s\d+/);
    return 0 if ($term =~ /^\p{kakko}$/);
    return 0 unless ($term =~ /\p{kakko}/);

    if ($term =~ /(\p{Symbol}|\p{Hiragana}|\p{Han}|\p{Katakana}|：|・|．|　|：|ー|％|・|．|\p{kakko})+$/) {
	return 1;
    } else {
	return 0;
    }
}

sub isAlphabetSequence {
    my ($term) = @_;

    if ($term =~ /^(\p{Latin}+?)(\+\p{Latin}+){9,}$/) {
	return 1;
    } else {
	return 0;
    }
}

sub isLongAlphabet {
    my ($term) = @_;

    if ($term =~ /^(\p{Latin}|：|・|．|　){15,}$/) {
	return 1;
    } else {
	return 0;
    }
}

sub isLongKatakana {
    my ($term) = @_;

    return 1 if ($term =~ /^(\p{Katakana}|：|ー|％|・|．|　|、){20,}$/);

    return 0;
}

sub isJapaneseTerm {
    my ($term) = @_;

    return 0 if ($term =~ /^(：|ー|％|・|．|　|\p{Symbol})+(<[^>]+>)?/);
    return 0 if ($term =~ /^(\p{kakko}){2,}/);

    if ($term =~ /^(s\d+:)?(\p{Latin}|\p{Number}|\p{Symbol}|\p{Hiragana}|\p{Katakana}|\p{Han}|\p{kakko}|：|ー|％|・|．|　|、|\+)+(<[^>]+>)?/) {
	return 1;
    } else {
	return 0;
    }
}
