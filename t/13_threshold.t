use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;

my $dbh = t::Util->new_dbh;

DBIx::QueryLog->threshold(1);

my $res = capture {
    $dbh->do('SELECT * FROM sqlite_master');
};

is $res, undef, 'query ok';

done_testing;
