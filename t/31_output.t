use strict;
use warnings;
use Test::Requires 'DBD::SQLite';
use Test::More;
use t::Util;
use DBIx::QueryLog;
use File::Temp qw(tempfile);
use IO::Handle;

my $dbh = t::Util->new_dbh;

subtest fh => sub {
    my $dbh = t::Util->new_dbh;
    my ($fh, $fname) = tempfile UNLINK => 1;
    $fh->autoflush(1);
    local $DBIx::QueryLog::OUTPUT = $fh;

    $dbh->do('SELECT * FROM sqlite_master');

    my $output = do {
        open my $rfh, '<', $fname or die $!;
        local $/; <$rfh>;
    };

    like $output, qr/SELECT \* FROM sqlite_master/, 'output ok';
};

subtest cb => sub {
    my %params;
    local $DBIx::QueryLog::OUTPUT = sub {
        %params = @_;
    };

    $dbh->do('SELECT * FROM sqlite_master');

    is $params{level}, 'debug', 'level';
    is $params{message}, sprintf("[%s] [%s] [%s] %s at %s line %s\n",
        @params{qw/localtime pkg time sql file line/}
    ), 'message';
};

done_testing;
