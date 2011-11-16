use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;

DBIx::QueryLog->compact(1);

my $dbh = t::Util->new_dbh;
my $res = capture {
my $stmt = << "SQL";
    SELECT  /* comment */     * , name ,
type  FROM \n   sqlite_master WHERE (\t type = ? AND   \n  name = ?  \r   )
OR   name = ? AND ( name <> ? ) AND
      type &

    ? AND name = "hoge '  ' "
SQL
    $dbh->do($stmt, undef, 'a b "c"', 'd ef', "fu '  ga1", 'a', 'b');
};

note $res;
my $expects = quotemeta join ' ',
    q|SELECT /* comment */ *, name, type FROM sqlite_master|,
    q|WHERE (type = 'a b "c"' AND name = 'd ef')|,
    q|OR name = 'fu ''  ga1'|,
    q|AND (name <> 'a')|,
    q|AND type & 'b'|,
    q|AND name = "hoge '  ' "|,
;

like $res, qr/$expects/, 'sql ok';

done_testing;
