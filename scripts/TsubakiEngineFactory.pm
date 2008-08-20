package TsubakiEngineFactory;

# $Id$

###################################################
# 用途に応じた TsubakiEngine を返すファクトリクラス
###################################################

use strict;
use Storable;

# 全文書数
my $N = 100132750;
# 平均文書長
my $AVE_DOC_LENGTH = 907.077; 
# my $AVE_DOC_LENGTH = 274.925; # for NTCIR3

# コンストラクタ
sub new {
    my ($class, $opts) = @_;
    my $this;
    if ($opts->{syngraph}) {
	# SynGraph 検索用 TsubakiEngine を返す
	require TsubakiEngine4SynGraphSearch;
	$this->{tsubaki} = new TsubakiEngine4SynGraphSearch({
	    idxdir => $opts->{idxdir},
	    dlengthdbdir => $opts->{dlengthdbdir},
	    skip_pos => $opts->{skippos},
	    verbose => $opts->{verbose},
	    average_doc_length => $AVE_DOC_LENGTH,
	    doc_length_dbs => &load_doc_length_dbs($opts->{dlengthdbdir}, $opts->{dlengthdb_hash}),
	    total_number_of_docs => $N,
	    weight_dpnd_score => $opts->{weight_dpnd_score},
	    score_verbose => $opts->{score_verbose},
	    logging_query_score => $opts->{logging_query_score},
	    idxdir4anchor => $opts->{idxdir4anchor},
	    dpnd_on => $opts->{dpnd_on},
	    dist_on => $opts->{dist_on},
	    show_speed => $opts->{show_speed}});
    } else {
	# 通常検索用 TsubakiEngine を返す
	require TsubakiEngine4OrdinarySearch;
	$this->{tsubaki} = new TsubakiEngine4OrdinarySearch({
	    idxdir => $opts->{idxdir},
	    dlengthdbdir => $opts->{dlengthdbdir},
	    skip_pos => $opts->{skippos},
	    verbose => $opts->{verbose},
	    average_doc_length => $AVE_DOC_LENGTH,
	    doc_length_dbs => &load_doc_length_dbs($opts->{dlengthdbdir}, $opts->{dlengthdb_hash}),
	    total_number_of_docs => $N,
	    weight_dpnd_score => $opts->{weight_dpnd_score},
	    show_speed => $opts->{show_speed},
	    score_verbose => $opts->{score_verbose},
	    logging_query_score => $opts->{logging_query_score},
	    idxdir4anchor => $opts->{idxdir4anchor},
	    dpnd_on => $opts->{dpnd_on},
	    dist_on => $opts->{dist_on}});
    }

    bless $this;
}

sub DESTROY {}

# 文書長 DB を読み込む
sub load_doc_length_dbs {
    my ($dir, $dlengthdb_hash) = @_;
    my @DOC_LENGTH_DBs;
    opendir(DIR, $dir);
    foreach my $dbf (readdir(DIR)) {
	next unless ($dbf =~ /doc_length\.bin/);

	my $fp = "$dir/$dbf";

	my $dlength_db;
	# 小規模なテスト用にdlengthのDBをハッシュでもつオプション
	if ($dlengthdb_hash) {
	    require CDB_File;
	    tie %{$dlength_db}, 'CDB_File', $fp or die "$0: can't tie to $fp $!\n";
	}
	else {
	    $dlength_db = retrieve($fp) or die "$!: $fp\n";
	}
	push(@DOC_LENGTH_DBs, $dlength_db);
    }
    closedir(DIR);
    return \@DOC_LENGTH_DBs;
}

# TsubakiEngine のインスタンスを返すファクトリメソッド
sub get_instance {
    my ($this) = @_;

    return $this->{tsubaki};
}

1;
