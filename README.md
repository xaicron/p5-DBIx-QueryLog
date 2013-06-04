# NAME

DBIx::QueryLog - Logging queries for DBI

# SYNOPSIS

    use DBIx::QueryLog;
    my $row = $dbh->selectrow_hashref('SELECT * FROM people WHERE user_id = ?', undef, qw/1986/);
    # => SELECT * FROM people WHERE user_id = '1986';

# DESCRIPTION

DBIx::QueryLog is logs each execution time and the actual query.

Currently, works on DBD::mysql, DBD::Pg and DBD::sqlite.

# CLASS METHODS

- threshold

    Logged if exceeding this value. (default not set)

        DBIx::QueryLog->threshold(0.1); # sec

    And, you can also specify `DBIX_QUERYLOG_THRESHOLD` environment variable.

- probability

    Run only once per defined value. (default not set)

        DBIx::QueryLog->probability(100); # about 1/100

    And, you can also specify `DBIX_QUERYLOG_PROBABILITY` environment variable.

- logger

    Sets logger class (e.g. [Log::Dispach](http://search.cpan.org/perldoc?Log::Dispach))

    Logger class must can be call \`log\` method.

        DBIx::QueryLog->logger($logger);

- skip\_bind

    If enabled, will be faster, but SQL is not bound.

        DBIx::QueryLog->skip_bind(1);
        my $row = $dbh->do(...);
        # => 'SELECT * FROM people WHERE user_id = ?' : [1986]

    And, you can also specify `DBIX_QUERYLOG_SKIP_BIND` environment variable.

- color

    If you want to colored SQL output are:

        DBIx::QueryLog->color('green');

    And, you can also specify `DBIX_QUERYLOG_COLOR` environment variable.

- useqq

    using `$Data::Dumper::Useqq`.

        DBIx::QueryLog->useqq(1);

    And, you can also specify `DBIX_QUERYLOG_USEQQ` environment variable.

- compact

    Compaction SQL.

        DBIx::QueryLog->compact(1);
        #  FROM: SELECT          *  FROM      foo WHERE bar = 'baz'
        #  TO  : SELECT * FROM foo WHERE bar = 'baz'

    And, you can also specify `DBIX_QUERYLOG_COMPACT` environment variable.

- explain

    __EXPERIMENTAL__

    Logged Explain.

    This feature requires `Text::ASCIITable` installed.

        DBIx::QueryLog->explain(1);
        my $row = $dbh->do(...);
        # => SELECT * FROM peaple WHERE user_id = '1986'
        #  .----------------------------------------------------------------------------------------------.
        #  | id | select_type | table  | type  | possible_keys | key     | key_len | ref   | rows | Extra |
        #  +----+-------------+--------+-------+---------------+---------+---------+-------+------+-------+
        #  |  1 | SIMPLE      | peaple | const | PRIMARY       | PRIMARY |       4 | const |    1 |       |
        #  '----+-------------+--------+-------+---------------+---------+---------+-------+------+-------'

    And, you can also specify `DBIX_QUERYLOG_EXPLAIN` environment variable.

- show\_data\_source

    if enabled, added DBI data\_source in default message.

        $dbh->do('SELECT * FROM sqlite_master');
        # [2012-03-09T00:58:23] [main] [0.000953] SELECT * FROM sqlite_master at foo.pl line 34

        DBIx::QueryLog->show_data_source(1);
        $dbh->do('SELECT * FROM sqlite_master');
        # [2012-03-09T00:58:23] [main] [0.000953] [SQLite:dbname=/tmp/TrSATdY3cc] SELECT * FROM sqlite_master at foo.pl line 56

    And, you can also specify `DBIX_QUERYLOG_SHOW_DATASOURCE` environment variable.

- guard

    Returned guard object.

        use DBIx::QueryLog ();
        {
            my $guard = DBIx::QueryLog->guard;
            # ... do something
        }

    This code same as are:

        use DBIx::QueryLog ();

        DBIx::QueryLog->enable;
        # ... do something
        DBIx::QueryLog->disable;

- ignore\_trace

    Returned guard object. Disable trace in the scope.

        use DBIx::QueryLog;

        # enabled
        $dbh->do(...);

        {
            my $guard = DBIx::QueryLog->ignore_trace;
            # disable
            $dbh->do(...);
        }

        # enabled
        $dbh->do(...)

- is\_enabled

    Return true or false

        use DBIx::QueryLog ();

        say DBIx::QueryLog->is_enabled;

        DBIx::QueryLog->disable;

    SEE ALSO [Localization](http://search.cpan.org/perldoc?Localization) section.

# TIPS

## Localization

If you want to localize the scope are:

    use DBIx::QueryLog (); # or require DBIx::QueryLog;

    DBIx::QueryLog->begin; # or DBIx::QueryLog->enable
    my $row = $dbh->do(...);
    DBIx::QueryLog->end;   # or DBIx::QueryLog->disable

Now you could enable logging between `begin` and `end`.

## LOG\_LEVEL

If you set `logger`, it might want to change the logging level.

It can be modified as follows:

    $DBIx::QueryLog::LOG_LEVEL = 'info'; # default 'debug'

## OUTPUT

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
    data_source: $s       # data_source
    sql        : %s       # executed query
    bind_params: %s       # bind parameters
    pkg        : %s       # caller package
    file       : %s       # caller file
    line       : %d       # caller line
    FORMAT

      printf $format,
          @params{qw/localtime level pkg time data_source sql/},
          join(', ', @{$params{bind_params}}),
          @params{qw/file line/};

        printf "AutoCommit?: %d\n", $params->{dbh}->{AutoCommit} ? 1 : 0;
    };

Default `$OUTPUT` is `STDERR`.

# AUTHOR

xaicron <xaicron {at} cpan.org>

# THANKS TO

tokuhirom

yibe

kamipo

tomi-ru

riywo

makamaka

# BUG REPORTING

Plese use github issues: [https://github.com/xaicron/p5-DBIx-QueryLog/issues](https://github.com/xaicron/p5-DBIx-QueryLog/issues).

# COPYRIGHT

Copyright 2010 - xaicron

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[DBI](http://search.cpan.org/perldoc?DBI)
