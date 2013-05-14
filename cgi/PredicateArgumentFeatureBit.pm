package PredicateArgumentFeatureBit;

use strict;
use utf8;

our %CASE_FEATURE_BIT = ();
our %DPND_TYPE_FEATURE_BIT = ();

# Stanford dependency
$CASE_FEATURE_BIT{nsubj}     = (2 ** 9);
$CASE_FEATURE_BIT{dobj}      = (2 ** 10);
$CASE_FEATURE_BIT{iobj}      = (2 ** 11);
$CASE_FEATURE_BIT{tmod}      = (2 ** 12);
$CASE_FEATURE_BIT{advmod}    = (2 ** 13);
$CASE_FEATURE_BIT{ccomp}     = (2 ** 14);
$CASE_FEATURE_BIT{prep_in}   = (2 ** 15);
$CASE_FEATURE_BIT{prep_to}   = (2 ** 16);
$CASE_FEATURE_BIT{prep_for}  = (2 ** 17);
$CASE_FEATURE_BIT{prep_on}   = (2 ** 18);
$CASE_FEATURE_BIT{prep_at}   = (2 ** 19);
$CASE_FEATURE_BIT{prep_with} = (2 ** 20);
$CASE_FEATURE_BIT{prep_as}   = (2 ** 21);
$CASE_FEATURE_BIT{prep_by}   = (2 ** 22);

$CASE_FEATURE_BIT{xsubj}     = $CASE_FEATURE_BIT{nsubj};
$CASE_FEATURE_BIT{csubj}     = $CASE_FEATURE_BIT{nsubj};
$CASE_FEATURE_BIT{xcomp}     = $CASE_FEATURE_BIT{ccomp};

$CASE_FEATURE_BIT{nsbjpass}  = $CASE_FEATURE_BIT{dobj};
$CASE_FEATURE_BIT{agent}     = $CASE_FEATURE_BIT{nsubj};


# KNP definition for Japanese
$CASE_FEATURE_BIT{ga}      = (2 ** 9);
$CASE_FEATURE_BIT{wo}      = (2 ** 10);
$CASE_FEATURE_BIT{ni}      = (2 ** 11);
$CASE_FEATURE_BIT{he}      = (2 ** 12);
$CASE_FEATURE_BIT{to}      = (2 ** 13);
$CASE_FEATURE_BIT{de}      = (2 ** 14);
$CASE_FEATURE_BIT{kara}    = (2 ** 15);
$CASE_FEATURE_BIT{made}    = (2 ** 16);
$CASE_FEATURE_BIT{yori}    = (2 ** 17);
$CASE_FEATURE_BIT{mod}     = (2 ** 18);
$CASE_FEATURE_BIT{time}    = (2 ** 19);
$CASE_FEATURE_BIT{no}      = (2 ** 20);
$CASE_FEATURE_BIT{nitsuku} = (2 ** 21);
$CASE_FEATURE_BIT{tosuru}  = (2 ** 22);
$CASE_FEATURE_BIT{other}   = (2 ** 23);

# for backward compatibility
$CASE_FEATURE_BIT{ガ}     = (2 ** 9);
$CASE_FEATURE_BIT{ヲ}     = (2 ** 10);
$CASE_FEATURE_BIT{ニ}     = (2 ** 11);
$CASE_FEATURE_BIT{ヘ}     = (2 ** 12);
$CASE_FEATURE_BIT{ト}     = (2 ** 13);
$CASE_FEATURE_BIT{デ}     = (2 ** 14);
$CASE_FEATURE_BIT{カラ}   = (2 ** 15);
$CASE_FEATURE_BIT{マデ}   = (2 ** 16);
$CASE_FEATURE_BIT{ヨリ}   = (2 ** 17);
$CASE_FEATURE_BIT{修飾}   = (2 ** 18);
$CASE_FEATURE_BIT{時間}   = (2 ** 19);
$CASE_FEATURE_BIT{ノ}     = (2 ** 20);
$CASE_FEATURE_BIT{ニツク} = (2 ** 21);
$CASE_FEATURE_BIT{トスル} = (2 ** 22);
$CASE_FEATURE_BIT{その他} = (2 ** 23);

$DPND_TYPE_FEATURE_BIT{未格}   = (2 ** 24);
$DPND_TYPE_FEATURE_BIT{連体}   = (2 ** 25);
$DPND_TYPE_FEATURE_BIT{省略}   = (2 ** 26);
$DPND_TYPE_FEATURE_BIT{受動}   = (2 ** 27);
$DPND_TYPE_FEATURE_BIT{使役}   = (2 ** 28);
$DPND_TYPE_FEATURE_BIT{可能}   = (2 ** 29);
$DPND_TYPE_FEATURE_BIT{自動}   = (2 ** 30);
$DPND_TYPE_FEATURE_BIT{授動詞} = (2 ** 31);

1;
