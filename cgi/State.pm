package State;

use strict;
use utf8;
use Configure;

my $CONFIG = Configure::get_instance();

sub new {
    my ($class) = @_;
    my $this = {
	checkIn => 0,
	checkOutCalled => 0
    };

    bless $this;
}

sub DESTROY {
    my ($this) = @_;

    unlink($CONFIG->{LOCK_FILE}) if (!$this->{checkOutCalled} && $this->{checkIn});
}

sub checkIn {
    my ($this) = @_;

    my $count = 0;
    while (!symlink($CONFIG->{DUMY_LOCK_FILE}, $CONFIG->{LOCK_FILE})) {
	$count++;
	sleep(1);
	if ($count > $CONFIG->{MAX_NUM_OF_RETRY} && $CONFIG->{MAX_NUM_OF_RETRY} > 0) {
	    return 0;
	}
    }

    $this->{checkIn} = 1;
    return 1;
}

sub checkOut {
    my ($this) = @_;

    unlink($CONFIG->{LOCK_FILE});
    $this->{checkOutCalled} = 1;
}

1;
