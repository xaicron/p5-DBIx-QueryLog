use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;
use File::Temp qw(tempfile);
use IO::Handle;

my ($fh, $fname) = tempfile UNLINK => 1;
$fh->autoflush(1);
$DBIx::QueryLog::OUTPUT = $fh;

my $dbh = t::Util->new_dbh;
$dbh->do('SELECT * FROM sqlite_master');

my $output = do {
    open my $rfh, '<', $fname or die $!;
    local $/; <$rfh>;
};

like $output, qr/SELECT \* FROM sqlite_master/, 'output ok';

done_testing;
