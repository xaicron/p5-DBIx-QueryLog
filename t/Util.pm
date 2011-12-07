package t::Util;

use strict;
use warnings;
use DBI;
use File::Temp qw/tempfile/;
use base 'Exporter';
use Benchmark qw/:hireswallclock/;
use IO::Handle;

our @EXPORT = qw/capture capture_logger cmpthese/;

BEGIN {
    # cleanup environment
    for my $key (keys %ENV) {
        next unless $key =~ /^DBIX_QUERYLOG_/;
        delete $ENV{$key};
    }
}

sub new_dbh {
    my ($fh, $file) = tempfile;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file",'','', {
        AutoCommit => 1,
        RaiseError => 1,
    });
    return $dbh;
}

sub new_logger {
    bless {}, 't::Util::Logger';
}

sub setup_mysqld {
    eval { require Test::mysqld; 1 } or return;
    my $mysqld;
    if (my $json = $ENV{__TEST_DBIxQueryLog}) {
        eval { require JSON; 1 } or return;
        my $obj = JSON::decode_json($json);
        $mysqld = bless $obj, 'Test::mysqld';
    }
    else {
        $mysqld = Test::mysqld->new(my_cnf => {
            'skip-networking' => '',
        }) or return;
    }
    return $mysqld;
}

sub capture(&) {
    my ($code) = @_;

    open my $fh, '>', \my $content;
    $fh->autoflush(1);
    local $DBIx::QueryLog::OUTPUT = $fh;
    $code->();
    close $fh;
    return $content;
}

sub capture_logger(&) {
    my ($code) = @_;

    my $content;

    my $logger = DBIx::QueryLog->logger;
    no strict 'refs';
    no warnings 'redefine';
    my $logger_class = ref $logger;
    *{"$logger_class\::log"} = sub {
        my ($class, %p) = @_;
        $content = $p{params};
    };

    $code->();

    return $content;
}

sub cmpthese {
    my $result = Benchmark::timethese(@_);
    for my $value (values %$result) {
        $value->[1] = $value->[2] = $value->[0];
    };
    Benchmark::cmpthese($result);
}

package t::Util::Logger;

sub log {
    die 'fix me';
}

1;
