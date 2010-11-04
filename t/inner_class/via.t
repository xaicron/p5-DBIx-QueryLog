use strict;
use warnings;
use Test::More;
use DBIx::QueryLog;

ok open(my $fh, '>:via(DBIx::QueryLogLayer)', \my $res), 'open ok';

sub test_layer {
    my %specs = @_;
    my ($input, $expects, $desc) = @specs{qw/input expects desc/};

    undef $res;
    subtest $desc => sub {
        print $fh $input;
        is $res, $expects, 'check res value';
        done_testing;
    };
}

test_layer(
    input   => 'foobar',
    expects => undef,
    desc    => 'not match',
);

test_layer(
    input   => 'Binding parameters: foo bar',
    expects => 'foo bar',
    desc    => 'match',
);

ok close $fh, 'close ok';

done_testing;
