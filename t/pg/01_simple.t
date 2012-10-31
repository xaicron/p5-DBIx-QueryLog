use strict;
use warnings;
use Test::Requires qw(DBD::Pg Test::postgresql);
use Test::More;
use Test::postgresql;
use t::Util;
use DBIx::QueryLog ();
use DBI;

my $pg = t::Util->setup_postgresql
    or plan skip_all => $Test::postgresql::errstr || 'failed setup_postgresql';

my $dbh = DBI->connect(
    $pg->dsn(dbname => 'test'), '', '',
    {
        AutoCommit => 1,
        RaiseError => 1,
    },
) or die $DBI::errstr;

DBIx::QueryLog->begin;

my $res = capture {
    $dbh->selectrow_hashref('SELECT * FROM user');
};

like $res, qr/SELECT \* FROM user/;

done_testing;
