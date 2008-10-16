package Logger;

# $Id$

# ログを保存するクラス

use strict;
use utf8;
use Time::HiRes;
use Configure;

# コンストラクタ
sub new {
    my ($class, $called_from_API) = @_;
    my $this;

    $this->{log} = {};
    $this->{start} = Time::HiRes::time;
    $this->{time_of_before_action} = $this->{start};
    $this->{owner} = ($called_from_API) ? 'API' : 'BROWSER';

    bless $this;
}

# デストラクタ
sub DESTROY {}

# ログの保存
sub close {
    my ($this, $file) = @_;
    my @keys = keys %{$this->{log}};
    if (scalar(@keys) > 0) {
	unless ($file) {
	    my $CONFIG = Configure::get_instance();
	    $file = $CONFIG->{LOG_FILE_PATH};
	}
	my $date = `date +%m%d-%H%M%S`; chomp ($date);

	my $param_str;
	foreach my $k (sort @keys) {
	    my $val = $this->{log}{$k};
	    next if ((ref $val) =~ /(ARRAY|HASH)/);
	    $param_str .= "$k=$val,";
	}

	my $total_time = sprintf("%.3f", Time::HiRes::time - $this->{start});
	$param_str .= "total=$total_time";

	open(LOG, ">> $file") or die;
	binmode(LOG, ':utf8');
	print LOG "$date $ENV{REMOTE_ADDR} $this->{owner} $param_str\n";
	close(LOG);
    }
}

sub getParameter {
    my ($this, $key) = @_;

    return $this->{log}{$key};
}

sub keys {
    my ($this) = @_;

    return keys %{$this->{log}};
}

# キーと値のペアをログに登録
sub setParameterAs {
    my ($this, $key, $val) = @_;

    my $isUpdate = exists($this->{log}{$key});

    $this->{log}{$key} = $val;
    return $isUpdate;
}

# 時間測定の仕切りなおし
sub clearTimer {
    my ($this) = @_;
    $this->{time_of_before_action} = Time::HiRes::time;
}

# 時間をログに保存
sub setTimeAs {
    my ($this, $key, $template) = @_;

    my $current_time = Time::HiRes::time;
    # 前回の操作との時間的な差分をとる
    my $execute_time = $current_time - $this->{time_of_before_action};

    $this->{time_of_before_action} = $current_time;
    my $val = ($template) ? sprintf($template, $execute_time) : $execute_time;

    return $this->setParameterAs($key, $val);
}

1;
