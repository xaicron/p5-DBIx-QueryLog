use inc::Module::Install;
name 'DBIx-QueryLog';
all_from 'lib/DBIx/QueryLog.pm';

requires 'DBI';
requires 'Data::Dump';
recommends 'DBD::mysql';
recommends 'DBD::sqlite';

test_requires 'Test::More', 0.96;
test_requires 'Test::Requires';

tests join q{ }, map { sprintf 't%s.t', '/*' x $_ } 1..3;
author_tests 'xt';

auto_include();
auto_set_repository();

WriteAll;
