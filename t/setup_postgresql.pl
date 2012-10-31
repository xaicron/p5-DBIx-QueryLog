use JSON;
use t::Util;
my $env = $ENV{__TEST_DBIxQueryLog};
$pg  = t::Util->setup_postgresql;
$env = $env ? decode_json($env) : {};
$ENV{__TEST_DBIxQueryLog} = encode_json { %$env, pg => { %$pg } } if $pg;
