use inc::Module::Install;
name 'DBIx-QueryLog';
all_from 'lib/DBIx/QueryLog.pm';

#requires '';

#build_requires '';
test_requires 'Test::More', 0.96;

tests join q{ }, map { sprintf 't%s.t', '/*' x $_ } 1..3;
author_tests 'xt';

auto_include();
auto_set_repository();

WriteAll;
