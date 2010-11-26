use JSON;
use t::Util;
$mysqld = t::Util->setup_mysqld;
$ENV{__TEST_DBIxQueryLog} = encode_json { %$mysqld } if $mysqld;
