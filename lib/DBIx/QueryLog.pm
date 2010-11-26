package DBIx::QueryLog;

use strict;
use warnings;
use 5.008_001;

use DBI;
use Data::Dump ();
use Time::HiRes qw(gettimeofday tv_interval);

our $VERSION = '0.05';

my $org_execute               = \&DBI::st::execute;
my $org_db_do                 = \&DBI::db::do;
my $org_db_selectall_arrayref = \&DBI::db::selectall_arrayref;
my $org_db_selectrow_arrayref = \&DBI::db::selectrow_arrayref;
my $org_db_selectrow_array    = \&DBI::db::selectrow_array;

my $has_mysql = eval { require DBD::mysql; 1 } ? 1 : 0;
my $pp_mode   = $INC{'DBI/PurePerl.pm'} ? 1 : 0;

our %SKIP_PKG_MAP = (
    'DBIx::QueryLog' => 1,
);
our $LOG_LEVEL = 'debug';

my $st_execute;
my $db_do;
my $selectall_arrayref;
my $selectrow_arrayref;
my $selectrow_array;

sub import {
    my ($class) = @_;

    $st_execute ||= $class->_st_execute($org_execute);
    $db_do      ||= $class->_db_do($org_db_do) if $has_mysql;
    unless ($pp_mode) {
        $selectall_arrayref ||= $class->_select_array($org_db_selectall_arrayref);
        $selectrow_arrayref ||= $class->_select_array($org_db_selectrow_arrayref);
        $selectrow_array    ||= $class->_select_array($org_db_selectrow_array, 1);
    }

    no warnings qw(redefine prototype);
    *DBI::st::execute = $st_execute;
    *DBI::db::do = $db_do if $has_mysql;
    unless ($pp_mode) {
        *DBI::db::selectall_arrayref = $selectall_arrayref;
        *DBI::db::selectrow_arrayref = $selectrow_arrayref;
        *DBI::db::selectrow_array    = $selectrow_array;
    }
}

sub unimport {
    no warnings qw(redefine prototype);
    *DBI::st::execute = $org_execute;
    *DBD::db::do = $org_db_do if $has_mysql;
    unless ($pp_mode) {
        *DBI::db::selectall_arrayref = $org_db_selectall_arrayref;
        *DBI::db::selectrow_arrayref = $org_db_selectrow_arrayref;
        *DBI::db::selectrow_array    = $org_db_selectrow_array;
    }
}

*begin = \&import;
*end   = \&unimport;

my $container = {};
for my $accessor (qw/logger threshold probability skip_bind/) {
    no strict 'refs';
    *{__PACKAGE__."::$accessor"} = sub {
        use strict 'refs';
        my ($class, $args) = @_;
        return $container->{$accessor} unless $args;
        $container->{$accessor} = $args;
    };
}

sub _st_execute {
    my ($class, $org) = @_;
    
    return sub {
        my $wantarray = wantarray ? 1 : 0;
        my $sth = shift;

        my $probability = $class->probability;
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($sth, @_);
        }

        my $tfh;
        my $ret = $sth->{Statement};
        if ($class->skip_bind) {
            $ret .= ' : ' . Data::Dump::dump(\@_) if @_;
        }
        else {
            my $dbh = $sth->{Database};
            if ($dbh->{Driver}{Name} eq 'mysql') {
                open $tfh, '>:via(DBIx::QueryLogLayer)', \$ret;
                $sth->trace('2|SQL', $tfh);
            }
            else {
                my $i = 0;
                $ret =~ s/\?/$dbh->quote($_[$i++])/eg;
            }
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($sth, @_)] : scalar $org->($sth, @_);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time);

        close $tfh if $tfh;
        return $wantarray ? @$res : $res;
    };
}

sub _select_array {
    my ($class, $org, $is_selectrow_array) = @_;

    return sub {
        my $wantarray = wantarray;
        my ($dbh, $stmt, $attr, @bind) = @_;

        my $probability = $class->probability;
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($dbh, $stmt, $attr, @bind);
        }

        my $tfh;
        my $ret = ref $stmt ? $stmt->{Statement} : $stmt;
        if ($class->skip_bind) {
            $ret .= ' : ' . Data::Dump::dump(\@bind) if @bind;
        }
        else {
            if ($dbh->{Driver}{Name} eq 'mysql') {
                open $tfh, '>:via(DBIx::QueryLogLayer)', \$ret;
                $dbh->trace('2|SQL', $tfh);
            }
            else {
                my $i = 0;
                $ret =~ s/\?/$dbh->quote($bind[$i++])/eg;
            }
        }

        my $begin = [gettimeofday];
        my $res;
        if ($is_selectrow_array) {
            $res = $wantarray ? [$org->($dbh, $stmt, $attr, @bind)] : $org->($dbh, $stmt, $attr, @bind);
        }
        else {
            $res = $org->($dbh, $stmt, $attr, @bind);
        }
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time);

        close $tfh if $tfh;
        if ($is_selectrow_array) {
            use Data::Dumper;
            warn Dumper $res;
            return $wantarray ? @$res : $res;
        }
        return $res;
    };
}

sub _db_do {
    my ($class, $org) = @_;

    return sub {
        my $wantarray = wantarray ? 1 : 0;
        my $dbh  = shift;
        my $stmt = shift;

        if ($dbh->{Driver}{Name} ne 'mysql') {
            return $org->($dbh, $stmt, @_); 
        }

        my $probability = $class->probability;
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($dbh, $stmt, @_);
        }

        my $tfh;
        my $ret = $stmt;
        if ($class->skip_bind) {
            $ret .= ' : ' . Data::Dump::dump([ @_[1..$#_] ]) if @_ > 1;
        }
        else {
            open $tfh, '>:via(DBIx::QueryLogLayer)', \$ret;
            $dbh->trace('2|SQL', $tfh);
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($dbh, $stmt, @_)] : scalar $org->($dbh, $stmt, @_);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time);

        close $tfh if $tfh;
        return $wantarray ? @$res : $res;
    };
}

sub _logging {
    my ($class, $ret, $time) = @_;

    my $threshold = $class->threshold;
    if (!$threshold || $time > $threshold) {
        my $caller = $class->_caller();
        my $message = sprintf "[%s] [%s] [%s] %s at %s line %s\n",
            scalar(localtime), $caller->{pkg}, $time, $ret, $caller->{file}, $caller->{line};

        my $logger = $class->logger;
        if ($logger) {
            $logger->log(
                level   => $LOG_LEVEL,
                message => $message,
                params  => {
                    time => $time,
                    sql  => $ret,
                    %$caller,
                }
            );
        }
        else {
            print STDERR $message;
        }
    }
}

sub _caller {
    my $i = 0;
    my $caller = { pkg => '???', line => '???', file => '???' };
    while (my @c = caller(++$i)) {
        if (!$SKIP_PKG_MAP{$c[0]} and $c[0] !~ /^DB[DI]::.*/) {
            $caller = { pkg => $c[0], file => $c[1], line => $c[2] };
            last;
        }
    }

    return $caller;
}

package PerlIO::via::DBIx::QueryLogLayer;

my $regex = qr/^Binding parameters: (.*)/ms;

sub PUSHED {
    my ($class, $mode, $fh) = @_;
    bless \my($logger), $class;
}

sub OPEN {
    my ($self, $path, $mode, $fh) = @_;
    $$self = $path;
    return 1;
}

sub WRITE {
    my ($self, $buf, $fh) = @_;

    return 0 unless $buf;

    if ($buf =~ $regex) {
        $buf = $1;
        $buf =~ s/\n$//;
        $$$self = $buf; # SQL
    }

    return 1;
}

sub CLOSE {
    my $self = shift;
    undef $$self;
    return 1;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

DBIx::QueryLog - Logging queries for DBI

=head1 SYNOPSIS

  use DBIx::QueryLog;
  my $row = $dbh->selectrow_hashref('SELECT * FROM people WHERE user_id = ?', undef, qw/1986/);
  # => SELECT * FROM people WHERE user_id = '1986';

=head1 DESCRIPTION

DBIx::QueryLog is logs each execution time and the actual query.

Currently, works on DBD::mysql and DBD::sqlite.

=head1 CLASS METHODS

=over

=item threshold

If exceed this value for logs. (default not set)

  DBIx::QueryLog->threshold(0.1); # sec

=item probability

Run once every "set value" times. (default not set)

  DBIx::QueryLog->probability(100); # about 1/100

=item logger

Sets logger class (e.g. L<Log::Dispach>)

Logger class must can be call `log` method.

  DBIx::QueryLog->logger($logger);

=item skip_bind

If enabled, will be faster.

But SQL is not bind.
The statement and bind-params are logs separately.

  DBIx::QueryLog->skip_bind(1);
  my $row = $dbh->do(...);
  # => 'SELECT * FROM people WHERE user_id = ?' : [1986]

=item begin

SEE ALSO L</Localization>

=item end

SEE ALSO L</Localization>

=back

=head1 TIPS

=head2 Localization

If you want to localize the scope are:

  use DBIx::QueryLog (); # or require DBIx::QueryLog;

  DBIx::QueryLog->begin;
  my $row = $dbh->do(...);
  DBIx::QueryLog->end;

Now you could enable logging between `begin` and `end`.

=head1 AUTHOR

xaicron E<lt>xaicron {at} cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2010 - xaicron

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<DBI>

=cut
