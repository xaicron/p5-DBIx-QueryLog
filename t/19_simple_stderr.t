use strict;
use warnings;
use Test::Requires 'DBD::SQLite', 'Test::Output';
use Test::More;
use t::Util;
use DBIx::QueryLog;

my $dbh = t::Util->new_dbh;

stderr_like(sub {$dbh->do('SELECT * FROM sqlite_master')},
		   qr/SELECT \* FROM sqlite_master/, 'SQL');

done_testing;
