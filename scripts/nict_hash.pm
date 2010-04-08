
package nict_hash;

use strict;
use warnings;

my $node_num = 120;

sub id2node(){
    my @id2node;
    for (my $i = 0 ; $i < $node_num ; $i++){
	$id2node[$i] = sprintf("iccc%03d", $i+11);
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
