package DBIx::QueryLog;

use strict;
use warnings;
use 5.008_001;

use DBI;
use Time::HiRes qw(gettimeofday tv_interval);

our $VERSION = '0.12';

my $org_execute               = \&DBI::st::execute;
my $org_bind_param            = \&DBI::st::bind_param;
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
my $st_bind_param;
my $db_do;
my $selectall_arrayref;
my $selectrow_arrayref;
my $selectrow_array;

sub import {
    my ($class) = @_;

    $st_execute    ||= $class->_st_execute($org_execute);
    $st_bind_param ||= $class->_st_bind_param($org_bind_param);
    $db_do         ||= $class->_db_do($org_db_do) if $has_mysql;
    unless ($pp_mode) {
        $selectall_arrayref ||= $class->_select_array($org_db_selectall_arrayref);
        $selectrow_arrayref ||= $class->_select_array($org_db_selectrow_arrayref);
        $selectrow_array    ||= $class->_select_array($org_db_selectrow_array, 1);
    }

    no warnings qw(redefine prototype);
    *DBI::st::execute    = $st_execute;
    *DBI::st::bind_param = $st_bind_param;
    *DBI::db::do         = $db_do if $has_mysql;
    unless ($pp_mode) {
        *DBI::db::selectall_arrayref = $selectall_arrayref;
        *DBI::db::selectrow_arrayref = $selectrow_arrayref;
        *DBI::db::selectrow_array    = $selectrow_array;
    }
}

sub unimport {
    no warnings qw(redefine prototype);
    *DBI::st::execute    = $org_execute;
    *DBI::st::bind_param = $org_bind_param;
    *DBI::db::do         = $org_db_do if $has_mysql;
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
        return $container->{$accessor} unless @_ > 1;
        $container->{$accessor} = $args;
    };
}

sub _st_execute {
    my ($class, $org) = @_;
    
    return sub {
        my $wantarray = wantarray ? 1 : 0;
        my $sth = shift;

        my $probability = $container->{probability};
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($sth, @_);
        }

        my $ret = $sth->{Statement};
        if ($container->{skip_bind}) {
            my @params;
            if (@_) {
                @params = @_;
            }
            elsif ($sth->{private_DBIx_QueryLog}) {
                for my $bind_param (@{$sth->{private_DBIx_QueryLog}}) {
                    my $value = $bind_param->[0];
                    push @params, $value;
                }
            }
            local $" = ', ';
            $ret .= " : [@params]" if @params;
        }
        else {
            my $dbh = $sth->{Database};
            if (@_) {
                $ret = _bind($dbh, $ret, \@_);
            }
            elsif ($sth->{private_DBIx_QueryLog}) {
                my (@params, @types);
                for my $bind_param (@{$sth->{private_DBIx_QueryLog}}) {
                    my $value = $bind_param->[0];
                    push @params, $bind_param->[0];
                    push @types, $bind_param->[1]{TYPE};
                }
                $ret = _bind($dbh, $ret, \@params, \@types);
            }
        }

        $sth->{private_DBIx_QueryLog} = undef if $sth->{private_DBIx_QueryLog};

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($sth, @_)] : scalar $org->($sth, @_);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time);

        return $wantarray ? @$res : $res;
    };
}

sub _st_bind_param {
    my ($class, $org) = @_;

    return sub {
        my ($sth, $p_num, $value, $attr) = @_;
        $sth->{private_DBIx_QueryLog} ||= [];
        $attr = +{ TYPE => $attr || 0 } unless ref $attr eq 'HASH';
        $sth->{private_DBIx_QueryLog}[$p_num - 1] = [$value, $attr];
        $org->(@_);
    };
}

sub _select_array {
    my ($class, $org, $is_selectrow_array) = @_;

    return sub {
        my $wantarray = wantarray;
        my ($dbh, $stmt, $attr, @bind) = @_;

        no warnings qw(redefine prototype);
        local *DBI::st::execute = $org_execute; # suppress duplicate logging

        my $probability = $container->{probability};
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($dbh, $stmt, $attr, @bind);
        }

        my $ret = ref $stmt ? $stmt->{Statement} : $stmt;
        if ($container->{skip_bind}) {
            local $" = ', ';
            $ret .= " : [@bind]" if @bind;
        }
        else {
            $ret = _bind($dbh, $ret, \@bind);
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

        if ($is_selectrow_array) {
            return $wantarray ? @$res : $res;
        }
        return $res;
    };
}

sub _db_do {
    my ($class, $org) = @_;

    return sub {
        my $wantarray = wantarray ? 1 : 0;
        my ($dbh, $stmt, $attr, @bind) = @_;

        if ($dbh->{Driver}{Name} ne 'mysql') {
            return $org->($dbh, $stmt, $attr, @bind);
        }

        my $probability = $container->{probability};
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($dbh, $stmt, $attr, @bind);
        }

        my $ret = $stmt;
        if ($container->{skip_bind}) {
            local $" = ', ';
            $ret .= " : [@bind]" if @bind;
        }
        else {
            $ret = _bind($dbh, $ret, \@bind);
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($dbh, $stmt, $attr, @bind)] : scalar $org->($dbh, $stmt, $attr, @bind);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time);

        return $wantarray ? @$res : $res;
    };
}

sub _bind {
    my ($dbh, $ret, $params, $types) = @_;
    $types ||= [];

    my $i = 0;
    if ($dbh->{Driver}{Name} eq 'mysql') {
        my $limit_flag = 0;
        $ret =~ s{([?)])}{
            if ($1 eq '?') {
                $limit_flag ||= do {
                    my $pos = pos $ret;
                    ($pos >= 6 && substr($ret, $pos - 6, 6) =~ /\A[Ll](?:IMIT|imit) \z/) ? 1 : 0;
                };
                $limit_flag ? $params->[$i++] : $dbh->quote($params->[$i], $types->[$i++]);
            }
            elsif ($1 eq ')') {
                $limit_flag = 0;
                ')';
            }
        }eg;
    }
    else {
        $ret =~ s/\?/$dbh->quote($params->[$i], $types->[$i++])/eg;
    }
    return $ret;
}

sub _logging {
    my ($class, $ret, $time) = @_;

    my $threshold = $container->{threshold};
    if (!$threshold || $time > $threshold) {
        my $i = 0;
        my $caller = { pkg => '???', line => '???', file => '???' };
        while (my @c = caller(++$i)) {
            if (!$SKIP_PKG_MAP{$c[0]} and $c[0] !~ /^DB[DI]::.*/) {
                $caller = { pkg => $c[0], file => $c[1], line => $c[2] };
                last;
            }
        }

        my $message = sprintf "[%s] [%s] [%s] %s at %s line %s\n",
            scalar(localtime), $caller->{pkg}, $time, $ret, $caller->{file}, $caller->{line};

        if (my $logger = $container->{logger}) {
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

=head2 LOG_LEVEL

If you want to change log_level are:

  $DBIx::QueryLog::LOG_LEVEL = 'info'; # default 'debug'

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
