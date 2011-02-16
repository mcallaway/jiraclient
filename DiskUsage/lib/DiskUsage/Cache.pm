
package DiskUsage::Cache;

use strict;
use warnings;
use Data::Dumper;

use English;

use Cwd 'abs_path';
use DBI;
use Time::HiRes qw(usleep);
use File::Basename;
use File::Find::Rule;

# -- Subroutines
#
sub new {
  my $class = shift;
  my $self = {
    parent => shift,
  };
  bless $self, $class;
  return $self;
}

sub error {
  # Raise an Exception object.
  my $self = shift;
  $self->{parent}->error(@_);
}

sub logger {
  # Raise an Exception object.
  my $self = shift;
  $self->{parent}->logger(@_);
}

sub local_debug {
  my $self = shift;
  $self->{parent}->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}

sub sql_exec {
  # Execute SQL.  Retry N times then give up.

  my $self = shift;
  my $sql = shift;

  my @args = ();
  @args = @_
    if $#_ > -1;

  my $dbh = $self->{dbh};
  my $sth;
  my $attempts = 0;

  $self->error("no database handle, run prep()\n")
    if (! defined $dbh);
  $self->error("no SQL provided\n")
    if (! defined $sql);

  while (1) {

    my $result;
    my $max_attempts = 3;

    $self->local_debug("sql_exec($sql) with args " . Dumper(@args) . "\n");

    eval {
      $sth = $dbh->prepare($sql);
    };
    if ($@) {
      $self->error("could not prepare sql: $@");
    }

    my $rows;
    eval {
      $sth->execute(@args);
      $rows = $sth->fetchall_arrayref();
    };
    if ($@) {
      $attempts += 1;
      if ($attempts >= $max_attempts) {
        $self->error("failed during execute $attempts times, giving up: $@\n");
      } else {
        $self->local_debug("failed during execute $attempts times, retrying: $@\n");
      }
      usleep(10000);
    } else {
      $self->local_debug("success: " . $sth->rows . ": " . Dumper($rows) . "\n");
      return $rows;
    }
  }
}

sub prep {
  # Connect to the cache.
  my $self = shift;
  my $cachefile = $self->{parent}->{cachefile};

  $self->local_debug("prep()\n");

  $self->error("cachefile is undefined, use -i\n")
    if (! defined $cachefile);
  if (-f $cachefile) {
    $self->local_debug("using existing cache $cachefile\n");
  } else {
    open(DB,">$cachefile") or
      $self->error("failed to create new cache $cachefile: $!\n");
    close(DB);
    $self->local_debug("creating new cache $cachefile\n");
  }

  my $connected = 0;
  my $retries = 0;
  my $max_retries = $self->{parent}->{db_tries};
  my $dsn = "DBI:SQLite:dbname=$cachefile";

  while (!$connected and $retries < $max_retries) {

    $self->local_debug("SQLite trying to connect: $retries: $cachefile\n");

    eval {
      $self->{dbh} = DBI->connect( $dsn,"","",
          {
            PrintError => 0,
            AutoCommit => 1,
            RaiseError => 1,
          }
        ) or $self->error("couldn't connect to database: " . $self->{dbh}->errstr);
      $connected = 1;
    };
    if ( $@ ) {
      $retries += 1;
      $self->local_debug("SQLite can't connect, retrying: $cachefile: $@\n");
      sleep(1);
    };

  }

  $self->error("SQLite can't connect after $max_retries tries, giving up\n")
    if (!$connected);

  $self->local_debug("Connected to: $cachefile\n");

  # disk_df table and triggers
  my $sql = "CREATE TABLE IF NOT EXISTS disk_df (df_id INTEGER PRIMARY KEY AUTOINCREMENT, mount_path VARCHAR(255), physical_path VARCHAR(255), total_kb UNSIGNED INTEGER NOT NULL DEFAULT 0, used_kb UNSIGNED INTEGER NOT NULL DEFAULT 0, group_name VARCHAR(255), created DATE, last_modified DATE)";
  $self->sql_exec($sql);

  # disk_hosts table and triggers
  $sql = "CREATE TABLE IF NOT EXISTS disk_hosts (host_id INTEGER PRIMARY KEY AUTOINCREMENT, hostname VARCHAR(255), snmp_ok UNSIGNED INTEGER NOT NULL DEFAULT 0, created DATE NOT NULL DEFAULT '0000-00-00 00:00:00', last_modified DATE NOT NULL DEFAULT '0000-00-00 00:00:00')";
  $self->sql_exec($sql);

  # path_to_host table, where can I find a given df_id?
  # note no PRIMARY KEY, df_id can repeat... we take precautions
  # to have only unique pairs: df_id -> host_id;
  $sql = "CREATE TABLE IF NOT EXISTS mount_to_host (df_id INTEGER, host_id INTEGER)";
  $self->sql_exec($sql);

  $sql = "CREATE TRIGGER IF NOT EXISTS disk_df_update_created AFTER INSERT ON disk_df BEGIN UPDATE disk_df SET created = DATETIME('NOW') where rowid = new.rowid; END;";
  $self->sql_exec($sql);

  $sql = "CREATE TRIGGER IF NOT EXISTS disk_df_update_last_modified AFTER UPDATE ON disk_df BEGIN UPDATE disk_df SET last_modified = DATETIME('NOW') where rowid = new.rowid; END;";
  $self->sql_exec($sql);

  # set created after insert
  $sql = "CREATE TRIGGER IF NOT EXISTS disk_hosts_update_created AFTER INSERT ON disk_hosts  BEGIN UPDATE disk_hosts SET created = DATETIME('NOW') where rowid = new.rowid; END;";
  $self->sql_exec($sql);

  # set last modified after insert if snmp_ok is 1
  $sql = "CREATE TRIGGER IF NOT EXISTS disk_hosts_insert_last_modified AFTER INSERT ON disk_hosts WHEN new.snmp_ok = 1 BEGIN UPDATE disk_hosts SET last_modified = DATETIME('NOW') where rowid = new.rowid; END;";
  $self->sql_exec($sql);

  # set last modified after update if snmp_ok is 1
  $sql = "CREATE TRIGGER IF NOT EXISTS disk_hosts_update_last_modified AFTER UPDATE OF snmp_ok ON disk_hosts WHEN new.snmp_ok = 1 BEGIN UPDATE disk_hosts SET last_modified = DATETIME('NOW') where rowid = new.rowid; END;";
  $self->sql_exec($sql);

}

sub link_volumes_to_host {
  my $self = shift;
  my $host_id = shift;
  my $result = shift;

  $self->local_debug("link_volumes_to_hosts($host_id,\$result)\n");

  # Get host_id of this host.
  #my $sql = "SELECT host_id FROM disk_hosts where hostname = ?";
  #my $res = $self->sql_exec($sql,($host) );
  #my $host_id = pop @{ pop @$res };

  foreach my $volume (keys %$result) {
    # Insert if not already present.
    my $mount_path = $result->{$volume}->{mount_path};

    my $sql = "SELECT df_id FROM disk_df WHERE mount_path = ?";
    my $res = $self->sql_exec($sql,($mount_path) );
    my $df_id = pop @{ pop @$res };

    $sql = "SELECT df_id,host_id FROM mount_to_host WHERE df_id = ? AND host_id = ?";
    $res  = $self->sql_exec($sql,($df_id,$host_id) );
    my $cnt = scalar @$res;
    if (! $cnt) {
      $sql = "INSERT INTO mount_to_host (df_id,host_id) VALUES (?,?)";
      $res = $self->sql_exec($sql,($df_id,$host_id));
    }
  }
}

sub disk_hosts_add {
  my $self = shift;
  my $host = shift;
  my $result = shift;
  my $err = shift;

  my $snmp_ok;
  if ($err) {
    $snmp_ok = -1;
  } else {
    $snmp_ok = scalar keys %$result ? 1 : 0;
  }

  $self->local_debug("disk_hosts_add($host,result,$err)\n");

  my $sql = "SELECT host_id FROM disk_hosts where hostname = ?";
  my $res = $self->sql_exec($sql,($host) );
  my $host_id;

  my @args = ();
  if ( $#$res == -1 ) {
    $sql = "INSERT INTO disk_hosts (hostname,snmp_ok) VALUES (?,?)";
    @args = ($host,$snmp_ok);
  } else {
    # trivial update triggers the trigger.
    $sql = "UPDATE disk_hosts SET hostname=?, snmp_ok=?  WHERE hostname=?";
    @args = ($host,$snmp_ok,$host);
  }
  # Do the insert or update
  $res = $self->sql_exec($sql,@args);

  # Now get the host_id
  $sql = "SELECT host_id FROM disk_hosts where hostname = ?";
  $res = $self->sql_exec($sql,($host) );
  $host_id = pop @{ pop @$res };

  # Update link table
  $self->link_volumes_to_host($host_id,$result);
}

sub disk_df_add {
  # Update cache, note insert or update.
  # params is a hash of df items:
  #   my $params = {
  #     'physical_path' => "/vol/sata800",
  #     'mount_path' => "/gscmnt/sata800",
  #     'total_kb' => 1000,
  #     'used_kb' => 900,
  #     'group_name' => 'PRODUCTION',
  #   };
  my $self = shift;
  my $params = shift;

  $self->local_debug("disk_df_add( " . Dumper($params) . ")\n");

  foreach my $key ( 'mount_path', 'physical_path', 'total_kb', 'used_kb', 'group_name' ) {
    $self->error("params is missing key: $key\n")
      if (! exists $params->{$key});
  }

  # Determine if row is present, and thus whether this is an
  # insert or update.
  my $sql = "SELECT df_id FROM disk_df where physical_path = ?";
  my $res = $self->sql_exec($sql,( $params->{'physical_path'} ) );

  my @args = ();
  if ( $#$res == -1 ) {
    $sql = "INSERT INTO disk_df
            (mount_path,physical_path,group_name,total_kb,used_kb)
            VALUES (?,?,?,?,?)";
    if (ref($params) eq 'HASH') {
      foreach my $key ( 'mount_path', 'physical_path', 'group_name', 'total_kb', 'used_kb' ) {
        push @args, $params->{$key}
          if (defined $params->{$key});
      }
    }
  } else {
    $sql = "UPDATE disk_df
            SET mount_path=?,group_name=?,total_kb=?,used_kb=?
            WHERE physical_path = ?";
    if (ref($params) eq 'HASH') {
      foreach my $key ( 'mount_path', 'group_name', 'total_kb', 'used_kb', 'physical_path' ) {
        push @args, $params->{$key}
          if (defined $params->{$key});
      }
    }
  }

  return $self->sql_exec($sql,@args);
}

sub fetch_disk_group {
  my $self = shift;
  my $mount_path = shift;

  my $sql = "SELECT group_name FROM disk_df WHERE mount_path = ?";
  $self->local_debug("fetch_disk_group($mount_path)\n");
  return $self->sql_exec($sql,($mount_path));
}

sub fetch {
  # Fetch an item from the cache.
  my $self = shift;
  my $key = shift;
  my $value = shift;

  my $sql = "SELECT * FROM disk_df WHERE $key = ?";
  $self->local_debug("fetch($sql)\n");
  return $self->sql_exec($sql,$value);
}

sub validate_volumes {
  # See if we have volumes that haven't been updated since maxage.
  my $self = shift;
  $self->local_debug("validate_volumes()\n");
  my $vol_maxage = $self->{parent}->{vol_maxage};
  my $sql = "SELECT physical_path, mount_path, last_modified FROM disk_df WHERE last_modified < date(\"now\",\"-$vol_maxage days\") ORDER BY last_modified";
  $self->local_debug("fetch($sql)\n");
  my $result = $self->sql_exec($sql);
  foreach my $row (@$result) {
    $self->logger("Aging volume: " . join(' ',@$row) . "\n");
  }
  return;
}

1;

