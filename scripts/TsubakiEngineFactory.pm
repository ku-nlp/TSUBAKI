package TsubakiEngineFactory;

# $Id$

###################################################
# 用途に応じた TsubakiEngine を返すファクトリクラス
###################################################

use strict;
use Storable;

use Configure;
my $CONFIG = Configure::get_instance();

# 全文書数
my $N = $CONFIG->{NUMBER_OF_DOCUMENTS};

# 平均文書長
my $AVE_DOC_LENGTH = $CONFIG->{AVERAGE_DOCUMENT_LENGTH};

# コンストラクタ
sub new {
    my ($class, $opts) = @_;
    my $this;

    # SynGraph 検索用 TsubakiEngine を返す
    require TsubakiEngine4SynGraphSearch;
    $this->{tsubaki} = new TsubakiEngine4SynGraphSearch({
	idxdir => $opts->{idxdir},
	dlengthdbdir => $opts->{dlengthdbdir},
	skip_pos => $opts->{skippos},
	verbose => $opts->{verbose},
	average_doc_length => $AVE_DOC_LENGTH,
	doc_length_dbs => $opts->{doc_length_dbs},
	pagerank_db => $opts->{pagerank_db},
	total_number_of_docs => $N,
	weight_dpnd_score => $opts->{weight_dpnd_score},
	score_verbose => $opts->{score_verbose},
	logging_query_score => $opts->{logging_query_score},
	idxdir4anchor => $opts->{idxdir4anchor},
	dpnd_on => $opts->{dpnd_on},
	dist_on => $opts->{dist_on},
	show_speed => $opts->{show_speed}});

    bless $this;
}

sub DESTROY {}

# TsubakiEngine のインスタンスを返すファクトリメソッド
sub get_instance {
    my ($this) = @_;

    return $this->{tsubaki};
}

1;
