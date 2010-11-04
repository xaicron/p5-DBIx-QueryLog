package t::Util;

use strict;
use warnings;
use DBI;
use File::Temp qw/tempfile/;
use base 'Exporter';

our @EXPORT = qw/capture capture_logger/;

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

sub capture(&) {
    my ($code) = @_;

    local *STDERR;
    open my $fh, '>', \my $content;
    *STDERR = $fh;
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

package t::Util::Logger;

sub log {
    die 'fix me';
}

1;
