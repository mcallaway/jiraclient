
package DiskUsage::Cache::TestSuite;

my $CLASS = __PACKAGE__;

# Standard modules for my unit test suites
# use base 'Test::Builder::Module';

use strict;
use warnings;

use Test::More tests => 17;
use Test::Output;
use Test::Exception;

use Class::MOP;
use Data::Dumper;
use Cwd;
use File::Basename;

use DiskUsage;
use DiskUsage::Cache;

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

# Determine if we're 'live' and can use LSF.
sub new {
  my $class = shift;
  my $self = {
    live => 0,
    debug => 0,
  };
  return bless $self, $class;
}

sub test_start {
  my $self = shift;
  my $obj = new DiskUsage;
  $obj->{configfile} = $cwd . "/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = $cwd . "/data/test.cache";
  $obj->{debug} = $self->{debug};
  #$obj->read_config();
  $obj->{diskconf} = "./t/data/good_disk_conf_001";
  $obj->{cachefile} = "./t/data/test.cache";
  $obj->prepare_logger();
  unlink($obj->{cachefile});
  $obj->{cache}->prep();
  return $obj->{cache};
}

sub test_logger {
  my $self = shift;
  # Test logging to stdout.
  my $obj = $self->test_start();
  $obj->{parent}->{debug} = 1;
  stdout_like { $obj->local_debug("Test") } qr/^.*: Test/, "test_logger: debug on ok";
  $obj->{parent}->{debug} = 0;
  stdout_isnt { $obj->local_debug("Test") } qr/^.*: Test/, "test_logger: debug off ok";
}

sub test_sql_exec {
  my $self = shift;
  my $cache = $self->test_start();

  # Sample data: df output
  my @args = ( "/gscmnt/sata920", "/vol/sata920", 6438993376, 5743812256);

  my $cachefile = $cache->{parent}->{cachefile};
  unlink($cachefile) if (-f $cachefile);
  $cache->prep();

  my $err = "SELECT SOME GOOFY WRONG STUFF";
  throws_ok { $cache->sql_exec($err,()) } qr/could not prepare/,"test_sql_exec: syntax error caught ok";

  $err = "SELECT bogus from disk_df;";
  throws_ok { $cache->sql_exec($err,()) } qr/could not prepare/,"test_sql_exec: no such column caught ok";

  my $insert = "INSERT INTO disk_df (mount_path,physical_path,total_kb,used_kb) VALUES (?,?,?,?)";
  lives_ok { $cache->sql_exec($insert,@args) } 'test_sql_exec: insert ok';

  my $count = "SELECT df_id from disk_df";
  lives_ok { $cache->sql_exec($count) } 'test_sql_exec: select ok';

  my $select = "SELECT total_kb FROM disk_df WHERE mount_path = ?";
  my $res = $cache->sql_exec($select,('/gscmnt/sata920'));
  #print Dumper($res);
  $res = $res->[0]->[0];
  #print Dumper($res);
  lives_and { is $res, 6438993376 } 'test_sql_exec: select ok';
  unlink "$cwd/data/test.cache";
  unlink "$cwd/data/total.rrd";
}

sub test_prep_bad_db_path {
  # Test creation of the cache DB.
  my $self = shift;
  my $cache = $self->test_start();

  # First ensure failure is caught
  $cache->{parent}->{cachefile} = "$cwd/bogus/path/foo";
  throws_ok { $cache->prep() } qr/failed to create/, "test_prep_bad_db_path: failure to connect caught";
}

sub test_prep_no_db {
  # Test creation of the cache DB.
  my $self = shift;
  my $cache = $self->test_start();

  # Test fetch before prep
  $cache->{dbh}->disconnect();
  $cache->{dbh} = undef;
  throws_ok { $cache->fetch('fake','fake') } qr/no database handle/, "test_prep_no_db: no database handle properly caught";
}

sub test_prep_good {
  # Test creation of the cache DB.
  my $self = shift;
  my $cache = $self->test_start();
  my $obj = $cache->{parent};
  # Enable debugging for this test to catch stdout
  $obj->{debug} = 1;
  my $cachefile;

  # Now do it right
  $cache->{parent}->{cachefile} = $cwd . "/data/test.cache";
  $cachefile = $cache->{parent}->{cachefile};
  unlink($cachefile) if (-f $cachefile);

  stdout_like { $cache->prep() } qr/creating new cache/, "new cache file correct";
  stdout_like { $cache->prep() } qr/using existing cache/, "existing cache file correct";
  ok(-f $cache->{parent}->{cachefile} == 1,"cache file present ok");
  unlink $cachefile;
}

sub test_add {
  my $self = shift;
  my $cache = $self->test_start();

  # Duplicate insert
  my $params = {
    'physical_path' => "/vol/sata800",
    'mount_path' => "/gscmnt/sata800",
    'total_kb' => 1000,
    'used_kb' => 900,
    'group_name' => 'DISK_TEST',
  };
  # Prepare cache
  $cache->prep();
  # Insert a row
  my $res = $cache->disk_df_add($params);
  # sleep to verify the update trigger
  sleep(2);
  # Insert the same row and validate it as an error.
  $params->{'used_kb'} = 999;
  $res = $cache->disk_df_add($params);
  $res = $cache->fetch('mount_path','/gscmnt/sata800');
  ok( $res->[0]->[4] = 999, "update and fetch work ok");
  # compare create vs. last modified
  ok( $res->[0]->[6] ne $res->[0]->[7], "update trigger works ok");
}

sub test_retry {
  my $self = shift;
  my $cache = $self->test_start();
  my $obj = $cache->{parent};

  # This test loops, and thus runs an indeterminate number
  # of times.  This is why we use done_testing() at the end.
  # We need an LSFSpool object for logger, debug, and config.
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = "$cwd/data/test.cache";
  $obj->{debug} = 0;
  #$obj->read_config();
  $obj->prepare_logger();

  # now, set cachefile so we cannot connect... see retry happen
  open(DB,">$obj->{cachefile}");
  close(DB);
  chmod 0000, $obj->{cachefile};
  throws_ok { $cache->prep() } qr/can't connect after \d tries, giving up/, "test_retry: fail to connect properly caught";
  chmod 0644, $obj->{cachefile};
  lives_ok { $cache->prep() } "test_retry: connect properly";
  unlink $obj->{cachefile};
}

sub test_validate_volumes {
  my $self = shift;
  my $cache = $self->test_start();
  my $obj = $cache->{parent};

  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = "$cwd/data/test.cache";
  $obj->{debug} = 0;
  $obj->{purge} = 30;
  #$obj->read_config();
  $obj->prepare_logger();

  my $params1 = {
    'physical_path' => "/vol/sata801",
    'mount_path' => "/gscmnt/sata801",
    'total_kb' => 1000,
    'used_kb' => 900,
    'group_name' => 'DISK_TEST',
  };
  my $params2 = {
    'physical_path' => "/vol/sata802",
    'mount_path' => "/gscmnt/sata802",
    'total_kb' => 11000,
    'used_kb' => 1900,
    'group_name' => 'DISK_TEST',
  };
  $cache->prep();
  my $res = $cache->disk_df_add($params1);
  $res = $cache->disk_df_add($params2);
  $cache->sql_exec("DROP TRIGGER IF EXISTS disk_df_update_last_modified");
  $cache->sql_exec("UPDATE disk_df SET last_modified = date('NOW','-40 days') WHERE physical_path = '/vol/sata801'");
  $cache->sql_exec("UPDATE disk_df SET last_modified = date('NOW','-40 days') WHERE physical_path = '/vol/sata802'");
  stdout_like { $cache->validate_volumes() } qr/Aging volume/, "aging volume correct";
  unlink "$cwd/data/disk_test.rrd";
  unlink "$cwd/data/disk_test1.rrd";
  unlink "$cwd/data/disk_test2.rrd";
  unlink $obj->{cachefile};
}

sub test_purge_volumes {
  my $self = shift;
  my $cache = $self->test_start();
  my $obj = $cache->{parent};

  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = "$cwd/data/test.cache";
  $obj->{debug} = 0;
  $obj->{purge} = 30;
  #$obj->read_config();
  $obj->prepare_logger();

  my $params1 = {
    'physical_path' => "/vol/sata801",
    'mount_path' => "/gscmnt/sata801",
    'total_kb' => 1000,
    'used_kb' => 900,
    'group_name' => 'DISK_TEST',
  };
  my $params2 = {
    'physical_path' => "/vol/sata802",
    'mount_path' => "/gscmnt/sata802",
    'total_kb' => 11000,
    'used_kb' => 1900,
    'group_name' => 'DISK_TEST',
  };
  $cache->prep();
  my $res = $cache->disk_df_add($params1);
  $res = $cache->disk_df_add($params2);
  $cache->sql_exec("DROP TRIGGER IF EXISTS disk_df_update_last_modified");
  $cache->sql_exec("UPDATE disk_df SET last_modified = date('NOW','-40 days') WHERE physical_path = '/vol/sata801'");
  $cache->sql_exec("UPDATE disk_df SET last_modified = date('NOW','-40 days') WHERE physical_path = '/vol/sata802'");
  $cache->purge_volumes();
  unlink "$cwd/data/disk_test.rrd";
  unlink "$cwd/data/disk_test1.rrd";
  unlink "$cwd/data/disk_test2.rrd";
  unlink $obj->{cachefile};
}

sub main {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('DiskUsage::Cache::TestSuite');
  foreach my $method ($meta->get_method_list()) {
    if ($method =~ m/^test_/) {
      $self->$method();
    }
  }
}

1;

package main;

use Getopt::Std;
use Class::MOP;

my $opts = {};
getopts("dlL",$opts) or
  die("failure parsing options: $!");

my $Test = $CLASS->new();

if ($opts->{'L'}) {
  $Test->{live} = 1;
}

if ($opts->{'d'}) {
  $Test->{debug} = 1;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('DiskUsage::Cache::TestSuite');
  foreach my $method ($meta->get_method_list()) {
    if ($method =~ m/^test_/) {
      print "$method\n";
    }
  }
  exit;
}

if (@ARGV) {
  my $test = $ARGV[0];
  if ($Test->can($test)) {
    print "Run $test\n";
    $Test->$test();
  } else {
    print "No test $test known\n";
  }
} else {
  print "run all tests\n";
  $Test->main();
}

