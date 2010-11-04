use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;

my $dbh = t::Util->new_dbh;

DBIx::QueryLog->probability(10);

my $count;
for (1..200) {
    my $res = capture {
        $dbh->do('SELECT * FROM sqlite_master');
    };
    $count++ if $res;
}
cmp_ok $count, '<', 200, 'less than';

done_testing;
