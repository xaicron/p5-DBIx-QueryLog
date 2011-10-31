use strict;
use warnings;
use Test::Requires 'DBD::SQLite', 'SQL::Tokenizer';
use Test::More;
use t::Util;
use DBIx::QueryLog;

DBIx::QueryLog->compact(1);

my $dbh = t::Util->new_dbh;
my $res = capture {
    $dbh->do("    SELECT       *  FROM \n   sqlite_master \t    \n    \r    ");
};

like $res, qr/SELECT \* FROM sqlite_master/, 'sql ok';

done_testing;
