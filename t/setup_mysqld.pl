use JSON;
use t::Util;
my $env = $ENV{__TEST_DBIxQueryLog};
$mysqld = t::Util->setup_mysqld;
$env = $env ? decode_json($env) : {};
$ENV{__TEST_DBIxQueryLog} = encode_json { %$env, mysql => { %$mysqld } } if $mysqld;
