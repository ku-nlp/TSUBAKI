package nict_hash;

use strict;
use warnings;

my $node_start = 11;
my $node_num = 120;

=head1 NAME

nict_hash - 検索対象/XML保持ノードの取得(ハッシュ関数)

=head1 SYNOPSIS

 use nict_hash;
 my $hash = nict_hash->new() or die;
 $hash->getnode("0000000001-1");

 perl -Mnict_hash -e '$hash=nict_hash->new(); print $hash->getnode("0000000001-1")."\n";'

=head1 METHOD

=over 4

=item getnode( STRING )

 * STRING に指定した sid から対象ノードを求める。
 * 入力: sid     (例) "0000000001-1"
 * 出力:ノード名 (例) "iccc011.crawl.kclab.jgn2.jp"
   ただし sid が不正な場合は "none" を出力

=back

=cut

sub id2node(){
    my @id2node;
    for (my $i = 0 ; $i < $node_num ; $i++){
	$id2node[$i] = sprintf("iccc%03d.crawl.kclab.jgn2.jp", $i+$node_start);
    }
    return \@id2node;
}

sub new () {
    my ($pkg, $hash) = @_;
    $hash->{node}= id2node();
    return   bless $hash;
}

sub hashf ($$){
    my ($pkg,$sid) =  @_;
    my $ref_sid = normalize($pkg,$sid);
    if (defined($ref_sid)){
	my $uid = $ref_sid->{uid};
	my $h = 0;
	for (my $i=0; $i < 10; $i=$i+2){
	    $h = $h * 137 + substr($uid,$i,2);
	}
	return $h % $node_num;
    }
    else {
	return undef;
    }
}


sub normalize($$){
    my ($pkg,$sid) = @_;
    my %normalized_sid ;
    my $uid;
    my $version;

    if ($sid =~ /^([0-9]{1,10})(-([0-9]+)){0,1}$/ ){
	$uid = $1;
	$version = $3;
    }
    else {
	return undef;
    }
    if (!defined($version) || $version eq "" || $version eq "0"){
	$normalized_sid{uid} = sprintf("%010d", $uid);
	$normalized_sid{version} = "0";
	$normalized_sid{sid} = sprintf("%010d", $uid);
    }
    else {
	$normalized_sid{uid} = sprintf("%010d", $uid);
	$normalized_sid{version} =  $version;
	$normalized_sid{sid} = sprintf("%010d-%d", $uid, $version);
    }
    return \%normalized_sid ;
}

sub getnode($$){
    my ($pkg,$sid) = @_;
    my $nodeid = hashf($pkg,$sid);
    if (defined($nodeid)){
	return $pkg->{node}[$nodeid];
    }
    else {
	return "none";
    }
}


1;
