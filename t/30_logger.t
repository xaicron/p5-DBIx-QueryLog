use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;

DBIx::QueryLog->logger(t::Util->new_logger);

my $dbh = t::Util->new_dbh;

my $res = capture_logger {
    $dbh->do('SELECT * FROM sqlite_master');
};

is $res->{sql}, 'SELECT * FROM sqlite_master', 'query ok';

done_testing;
