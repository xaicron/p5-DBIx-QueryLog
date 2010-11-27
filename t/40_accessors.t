use strict;
use warnings;
use Test::More;
use DBIx::QueryLog;

DBIx::QueryLog->skip_bind(1);
is +DBIx::QueryLog->skip_bind(), 1, 'set 1';
DBIx::QueryLog->skip_bind(0);
is +DBIx::QueryLog->skip_bind(), 0, 'set 0';
DBIx::QueryLog->skip_bind(undef);
is +DBIx::QueryLog->skip_bind(), undef, 'set undef';

done_testing;
