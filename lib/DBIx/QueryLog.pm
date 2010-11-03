package DBIx::QueryLog;

use strict;
use warnings;
use 5.008_001;

use DBI;
use Data::Dump ();
use Time::HiRes qw(gettimeofday tv_interval);
use POSIX qw(strftime);

our $VERSION = '0.01';

my $org_execute = \&DBI::st::execute;

our %SKIP_PKG_MAP = (
    'DBIx::QueryLog' => 1,
);

my $mysql_pattern  = qr/^Binding parameters: (.*)$/;
my $sqlite_pattern = qr/^sqlite trace: executing (.*) at dbdimp\.c line \d+$/;
our $PATTERN = qr/$mysql_pattern | $sqlite_pattern/x;

sub import {
    my ($class) = @_;

    no warnings 'redefine';
    *DBI::st::execute = sub {
        use warnings 'redefine';

        my $wantarray = wantarray ? 1 : 0;
        my $sth = shift;

        my $probability = $class->probability;
        if ($probability && int(rand() * $probability) % $probability != 0) {
            return $org_execute->($sth, @_);
        }

        my ($ret, $tfh);
        if ($class->skip_bind) {
            $ret  = $sth->{Statement};
            $ret .= ' : ' . Data::Dump::dump(\@_) if @_;
        }
        else {
            open $tfh, '>:via(DBIx::QueryLogLayer)', \$ret;
            $sth->trace('3', $tfh);
        }

        my $begin = [gettimeofday];
        my $res = $wantarray ? [$org_execute->($sth, @_)] : scalar $org_execute->($sth, @_);

        if (length $ret) {
            my $threshold = $class->threshold;
            my $time = sprintf '%.6f', tv_interval $begin, [gettimeofday];
            if (!$threshold || $time > $threshold) {
                my $caller = $class->_caller();
                my $message = sprintf "[%s] [%s] [%s] %s at %s line %s\n",
                    strftime("%FT%T", localtime), $caller->{pkg}, $time, $ret, $caller->{file}, $caller->{line};

                my $logger = $class->logger;
                if ($logger) {
                    $logger->log(
                        level   => 'debug',
                        message => $message,
                        time    => $time,
                        %$ret,
                    );
                }
                else {
                    print STDERR $message;
                }
            }
        }

        close $tfh if $tfh;
        return $wantarray ? @$res : $res;
    };
}

sub unimport {
    no warnings 'redefine';
    *DBI::st::execute = $org_execute;
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

    if ($buf && $buf =~ /$PATTERN/o) {
        $buf = $+;
        $buf =~ s/\n$//;
        $$$self = $buf; # SQL
    }

    return 1;
}

sub CLOSE {
    my $self = shift;
    undef $$self;
    return 0;
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

=item probability

Run once every "set value" times. (default not set)

=item logger

Sets logger class (e.g. Log::Dispach)

=item skip_bind

If enabled, will be faster.

But SQL is not bind.
The statement and bind-params are logs separately.

  DBIx::QueryLog->skip_bind(1);
  my $row = $dbh->do(...);
  # => 'SELECT * FROM people WHERE user_id = ?' : [1986]

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
