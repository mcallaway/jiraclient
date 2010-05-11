
package LSFSpool::Cache;

use strict;
use warnings;
use Data::Dumper;
use Error qw(:try);

use English;

# Path handling
use Cwd 'abs_path';
# For DB SQLite
use DBI;
# For usleep in DB retries
use Time::HiRes qw(usleep);
# For basename and dirname
use File::Basename;
# For find like functionality
use File::Find::Rule;

# -- Subroutines
#
sub new() {
  my $class = shift;
  my $self = {
    parent => shift,
  };
  bless $self, $class;
  return $self;
}

sub logger {
  # Simple logging where logfile is set during startup
  # to either a file handle or STDOUT.
  my $self = shift;
  my $fh = $self->{parent}->{logfile};
  print $fh localtime() . ": @_";
}

sub debug($) {
  # Simple debugging.
  my $self = shift;
  $self->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}

sub sql_exec {
  # Execute SQL N times.
  my $self = shift;
  my $sql = shift;
  my @args = @_;
  my $dbh = $self->{dbh};
  my $attempts = 0;
  my $sth;

  $self->debug("sql_exec($sql)\n");

  throw Error::Simple("no database handle, run prep()\n")
    if (! defined $dbh);

  while (1) {

    my $result;
    my $max_attempts = 3;

    try {
      $sth = $dbh->prepare($sql);
    } catch Error with {
      throw Error::Simple("could not prepare sql " . $DBI::errstr . "\n");
    };

    # The following is funky because for some reason return() does not
    # retrun from within a try {} block.  The code would execute N times
    # even if return $sth->fetchrow_array() was called.
    my @row;
    try {
      $sth->execute(@args);
      @row = $sth->fetchrow_array();
    } catch Error with { };
    # Note: we expect only one row
    if ($sth->err()) {
      $attempts += 1;
      if ($attempts >= $max_attempts) {
        $self->logger("failed during execute, giving up\n");
        return ();
      }
      usleep(10000);
    } else {
      return @row;
    }
  }
}

sub prep {
  # Connect to the cache.
  # Why are we doing this cache business?
  # It takes a long time to validate 'completeness' for a spool,
  # so much time that we want to remember it from run to run.
  # We started by saving state to a flat file, but we quickly needed
  # to save more complicated data, run count, time of check, completeness.
  # This turned into a "hash of hashes".  Flat file was no longer appropriate.
  # Perl tie can't handle a hash of hashes, but MLDBM tie advertises that it
  # can, but it had significant bugs that made it unreliable.  SQLite is
  # a fast and easy way for us to keep state over a long run.
  # Note we don't care much about normalized table forms.  Just save the data.
  my $self = shift;
  $self->debug("prep()\n");

  my $cachefile = $self->{parent}->{cachefile};

  if (-f $cachefile) {
    $self->logger("using existing cache $cachefile\n");
  } else {
    open(DB,">$cachefile") or
      throw Error::Simple("failed to create new cache $cachefile: $!\n");
    close(DB);
    $self->logger("creating new cache $cachefile\n");
  }

  my $connected = 0;
  my $retries = 0;
  my $max_retries = $self->{parent}->{config}->{db_tries};
  my $dsn = "DBI:SQLite:dbname=$cachefile";
  while (!$connected and $retries < $max_retries) {
    $self->logger("SQLite trying to connect: $retries: $cachefile\n");
    try {
      $self->{dbh} = DBI->connect( $dsn,"","",
          {
            PrintError => 0,
            AutoCommit => 1,
            RaiseError => 1,
          }
        ) or throw Error::Simple("couldn't connect to database: " . $self->{dbh}->errstr);
      # Use a sentinel instead of "last" to avoid warnings about,
      # "exited subroutine via last"
      $connected = 1;
    } catch Error with {
      $retries += 1;
      $self->logger("SQLite can't connect, retrying: $cachefile: $!\n");
      sleep(1);
    };
  }

  throw Error::Simple("SQLite can't connect after $max_retries tries, giving up\n")
    if (!$connected);

  $self->debug("Connected to: $cachefile\n");

  # FIXME: review the DB table format, what might be better?
  # FIXME: Add insertion time, modification time.
  my $sql = "CREATE TABLE IF NOT EXISTS spools (spoolname VARCHAR PRIMARY KEY, time VARCHAR(255), count INT UNSIGNED NOT NULL DEFAULT 0, complete SMALL NOT NULL DEFAULT 0, files VARCHAR)";
  return $self->sql_exec($sql);
}

sub add {
  # Update cache, note insert or update.

  my $self = shift;
  my $spoolname = shift;
  my $key = shift;
  my $value = shift;
  my $sql;

  $self->debug("add($spoolname,$key,$value)\n");

  $sql = "SELECT COUNT(*) FROM spools where spoolname = ?";
  my @result = $self->sql_exec($sql,($spoolname));

  if ( $result[0] == 0 ) {
    $sql = "INSERT INTO spools
            ($key,spoolname)
            VALUES (?,?)";
  } else {
    $sql = "UPDATE spools
            SET $key = ?
            WHERE spoolname = ?";
  }

  return $self->sql_exec($sql,($value,$spoolname));
}

sub del {
  # Set a cache value to blank.
  # Currently only used for 'files' field.
  my $self = shift;
  my $spoolname = shift;
  my $key = shift;

  $self->debug("del($spoolname,$key)\n");
  my $sql = "UPDATE spools SET $key = '' WHERE spoolname = ?";
  return $self->sql_exec($sql,($spoolname));
}

sub counter {
  # Increment the 'counter' field.
  my $self = shift;
  my $spoolname = shift;
  $self->debug("counter($spoolname)\n");

  my $sql = "UPDATE spools SET count=count+1 WHERE spoolname=?";
  return $self->sql_exec($sql,($spoolname))
}

sub fetch_complete {
  # The 'complete' field is special in that we sometimes want
  # to know 'complete' across all spools, not for one spool.
  my $self = shift;
  my $value = shift;
  $self->debug("fetch_complete($value)\n");
  my $sql = "SELECT spoolname FROM spools WHERE complete = ?";
  return $self->sql_exec($sql,($value));
}

sub count {
  my $self = shift;
  my $spoolname = shift;
  $self->debug("count($spoolname)\n");
  my $sql = "SELECT count(*) FROM spools WHERE spoolname = ?";
  return $self->sql_exec($sql,($spoolname));
}

sub fetch {
  # Fetch an item from the cache.
  my $self = shift;
  my $spoolname = shift;
  my $key = shift;
  my $value = shift;
  my $sql;
  $self->debug("fetch($spoolname,$key)\n");

  if (defined $value) {
    $sql = "SELECT * FROM spools WHERE spoolname = ? AND $key = ?";
    return $self->sql_exec($sql,($spoolname,$value));
  } else {
    $sql = "SELECT $key FROM spools WHERE spoolname = ?";
    return $self->sql_exec($sql,($spoolname));
  }
}

1;

__END__

=pod

=head1 NAME

LSFSpool::Cache - A class representing an LSF Spool Cache.

=head1 SYNOPSIS

  use LSFSpool::Cache
  my $suite = new LSFSpool::Cache

=head1 DESCRIPTION

This simple caching mechanism implements an SQLite database to save the
progress of an LSF Spool.

=head1 CLASS METHODS

=over

=item new()

Instantiates the class.

=item logger()

Trivial class' logger().

=item debug()

Trivial class' debugging.

=item sql_exec()

Execute an SQL statement.

=item prep()

Prepare the database, creating tables if not already present.

=item add()

Add an item to the cache using INSERT or UPDATE.

=item del()

Delete an item from the cache.

=item counter()

Increment the 'count' field.

=item fetch_complete()

Fetch all spools with a specified value of 'complete'.

=item count()

Execute a COUNT.

=item fetch()

Fetch an item from the cache.

=back

=head1 AUTHOR

Matthew Callaway (mcallawa@genome.wustl.edu)

=head1 COPYRIGHT

Copyright (c) 2010, Matthew Callaway. All Rights Reserved.  This module is free
software. It may be used, redistributed and/or modified under the terms of the
Perl Artistic License (see http://www.perl.com/perl/misc/Artistic.html)

=cut
