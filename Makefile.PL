use inc::Module::Install;
name 'DBIx-QueryLog';
all_from 'lib/DBIx/QueryLog.pm';

requires 'DBI';
recommends 'DBD::mysql';
recommends 'DBD::sqlite';
recommends 'Text::ASCIITable';

test_requires 'Test::More', 0.96;
test_requires 'Test::Requires';

tests join q{ }, map { sprintf 't%s.t', '/*' x $_ } 1..3;
author_tests 'xt';

repository 'https://github.com/xaicron/p5-DBIx-QueryLog';
bugtracker 'https://github.com/xaicron/p5-DBIx-QueryLog/issues';

if ((can_use 'Test::mysqld' or can_use 'Test::PostgreSQL') and can_use 'JSON') {
    my @pls;
    push @pls, 't/setup_mysqld.pl'     if can_use 'Test::mysqld';
    push @pls, 't/setup_postgresql.pl' if can_use 'Test::PostgreSQL';
    default_test_target(
        run_on_prepare => \@pls,
    );
}

WriteAll;
