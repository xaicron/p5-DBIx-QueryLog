package DBIx::QueryLog;

use strict;
use warnings;
use 5.008_001;

use DBI;
use Time::HiRes qw(gettimeofday tv_interval);
use Term::ANSIColor qw(colored);
use Data::Dumper ();

$ENV{ANSI_COLORS_DISABLED} = 1 if $^O eq 'MSWin32';

our $VERSION = '0.22';

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
our $OUTPUT    = *STDERR;

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

*enable  = *begin = \&import;
*disable = *end   = \&unimport;

my $container = {};
for my $accessor (qw/logger threshold probability skip_bind color useqq compact/) {
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
        my @params = @_;
        my @types;

        my $probability = $container->{probability};
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org->($sth, @params);
        }

        my $ret = $sth->{Statement};
        if (my $attrs = $sth->{private_DBIx_QueryLog_attrs}) {
            my $bind_params = $sth->{private_DBIx_QueryLog_params};
            for my $i (1..@$attrs) {
                push @types, $attrs->[$i - 1]{TYPE};
                push @params, $bind_params->[$i - 1] if $bind_params;
            }
        }
        $sth->{private_DBIx_QueryLog_params} = undef;

        unless ($container->{skip_bind} && @params) {
            my $dbh = $sth->{Database};
            $ret = _bind($dbh, $ret, \@params, \@types);
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($sth, @_)] : scalar $org->($sth, @_);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time, \@params);

        return $wantarray ? @$res : $res;
    };
}

sub _st_bind_param {
    my ($class, $org) = @_;

    return sub {
        my ($sth, $p_num, $value, $attr) = @_;
        $sth->{private_DBIx_QueryLog_params} ||= [];
        $sth->{private_DBIx_QueryLog_attrs } ||= [];
        $attr = +{ TYPE => $attr || 0 } unless ref $attr eq 'HASH';
        $sth->{private_DBIx_QueryLog_params}[$p_num - 1] = $value;
        $sth->{private_DBIx_QueryLog_attrs }[$p_num - 1] = $attr;
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
        unless ($container->{skip_bind} && @bind) {
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

        $class->_logging($ret, $time, \@bind);

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
        unless ($container->{skip_bind} && @bind) {
            $ret = _bind($dbh, $ret, \@bind);
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org->($dbh, $stmt, $attr, @bind)] : scalar $org->($dbh, $stmt, $attr, @bind);
        my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];

        $class->_logging($ret, $time, \@bind);

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
    my ($class, $ret, $time, $bind_params) = @_;

    my $threshold = $container->{threshold};
    return unless !$threshold || $time > $threshold;

    $bind_params ||= [];

    my $i = 0;
    my $caller = { pkg => '???', line => '???', file => '???' };
    while (my @c = caller(++$i)) {
        if (!$SKIP_PKG_MAP{$c[0]} and $c[0] !~ /^DB[DI]::/) {
            $caller = { pkg => $c[0], file => $c[1], line => $c[2] };
            last;
        }
    }

    my $sql = $ret;
    if ($container->{skip_bind}) {
        local $" = ', ';
        $ret .= " : [@$bind_params]" if @$bind_params;
    }

    if ($container->{compact} || $ENV{DBIX_QUERYLOG_COMPACT}) {
        my ($buff, $i) = ('', 0);
        my $skip_space    = 0;
        my $before_escape = 0;
        my $quote_char    = '';
        for (my ($i, $l) = (0, length $ret); $i < $l; ++$i) {
            my $s = substr $ret, $i, 1;
            if (!$quote_char && ($s eq q{ }||$s eq "\n"||$s eq "\t"||$s eq "\r")) {
                next if $skip_space;
                $buff .= q{ };
                $skip_space = 1;
                next;
            }
            elsif ($s eq q{'} || $s eq q{"}) {
                unless ($quote_char) {
                    $quote_char = $s;
                }
                elsif (!$before_escape && $s eq $quote_char) {
                    $quote_char = '';
                }
                else {
                    $before_escape = 0;
                }
            }
            elsif (!$before_escape && $quote_char && $s eq q{\\}) {
                $before_escape = 1;
            }
            elsif (!$quote_char) {
                if ($s eq q{(}) {
                    $buff .= $s;
                    $skip_space = 1;
                    next;
                }
                elsif (($s eq q{)}||$s eq q{,}) && substr($buff, -1, 1) eq q{ }) {
                    substr($buff, -1, 1) = '';
                }
            }
            $buff .= $s;
            $skip_space = 0;
        }
        ($ret = $buff) =~ s/^\s|\s$//g;
    }

    if ($container->{useqq} || $ENV{DBIX_QUERYLOG_USEQQ}) {
        local $Data::Dumper::Useqq  = 1;
        local $Data::Dumper::Terse  = 1;
        local $Data::Dumper::Indent = 0;
        $ret = Data::Dumper::Dumper($ret);
    }

    my $color = $container->{color} || $ENV{DBIX_QUERYLOG_COLOR};
    my $localtime = do {
        my ($sec, $min, $hour, $day, $mon, $year) = localtime;
        sprintf '%d-%02d-%02dT%02d:%02d:%02d', $year + 1900, $mon + 1, $day, $hour, $min, $sec;
    };
    my $message = sprintf "[%s] [%s] [%s] %s at %s line %s\n",
        $localtime, $caller->{pkg}, $time,
        $color ? colored([$color], $ret) : $ret,
        $caller->{file}, $caller->{line};

    if (my $logger = $container->{logger}) {
        $logger->log(
            level   => $LOG_LEVEL,
            message => $message,
            params  => {
                localtime   => $localtime,
                time        => $time,
                sql         => $sql,
                bind_params => $bind_params,
                %$caller,
            },
        );
    }
    else {
        if (ref $OUTPUT eq 'CODE') {
            $OUTPUT->(
                level       => $LOG_LEVEL,
                message     => $message,
                localtime   => $localtime,
                time        => $time,
                sql         => $sql,
                bind_params => $bind_params,
                %$caller,
            );
        }
        else {
            print {$OUTPUT} $message;
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

Logged if exceeding this value. (default not set)

  DBIx::QueryLog->threshold(0.1); # sec

=item probability

Run only once per defined value. (default not set)

  DBIx::QueryLog->probability(100); # about 1/100

=item logger

Sets logger class (e.g. L<Log::Dispach>)

Logger class must can be call `log` method.

  DBIx::QueryLog->logger($logger);

=item skip_bind

If enabled, will be faster, but SQL is not bound.

  DBIx::QueryLog->skip_bind(1);
  my $row = $dbh->do(...);
  # => 'SELECT * FROM people WHERE user_id = ?' : [1986]

=item color

If you want to colored SQL output are:

  DBIx::QueryLog->color('green');

And, you can also specify C<< DBIX_QUERYLOG_COLOR >> environment variable.

=item useqq

using C<< $Data::Dumper::Useqq >>.

  DBIx::QueryLog->useqq(1);

And, you can also specify C<< DBIX_QUERYLOG_USEQQ >> environment variable.

=item compact

Compaction SQL.

  DBIx::QueryLog->compact(1);
  #  FROM: SELECT          *  FROM      foo WHERE bar = 'baz'
  #  TO  : SELECT * FROM foo WHERE bar = 'baz'

And, you can also specify C<< DBIX_QUERYLOG_COMPACT >> environment variable.

=back

=head1 TIPS

=head2 Localization

If you want to localize the scope are:

  use DBIx::QueryLog (); # or require DBIx::QueryLog;

  DBIx::QueryLog->begin; # or DBIx::QueryLog->enable
  my $row = $dbh->do(...);
  DBIx::QueryLog->end;   # or DBIx::QueryLog->disable

Now you could enable logging between C<< begin >> and C<< end >>.

=head2 LOG_LEVEL

If you set C<< logger >>, it might want to change the logging level.

It can be modified as follows:

  $DBIx::QueryLog::LOG_LEVEL = 'info'; # default 'debug'

=head2 OUTPUT

If you want to change of output are:

  open my $fh, '>', 'dbix_query.log';
  $DBIx::QueryLog::OUTPUT = $fh;

or you can specify code reference:

  $DBIx::QueryLog::OUTPUT = sub {
      my %params = @_;

      my $format = << 'FORMAT';
  localtime  : %s       # ISO-8601 without timezone
  level      : %s       # log level ($DBIx::QueryLog::LOG_LEVEL)
  time       : %f       # elasped time
  sql        : %s       # executed query
  bind_params: %s       # bind parameters
  pkg        : %s       # caller package
  file       : %s       # caller file
  line       : %d       # caller line
  FORMAT

      printf $format,
          @params{qw/localtime level pkg time sql/},
          join(', ', @{$params{bind_params}}),
          @params{qw/file line/};
  };

Default C<< $OUTPUT >> is C<< STDERR >>.

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
