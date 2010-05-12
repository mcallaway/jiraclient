# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

use strict;
use warnings;

use Test::More tests => 25;
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Cwd;
use File::Basename;

BEGIN { use_ok('LSFSpool'); use_ok('LSFSpool::Cache'); };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub test_start {
  # We need an LSFSpool object for logger, debug, and config.
  my $spooler = new LSFSpool;
  $spooler->{configfile} = "lsf_spool_good_1.cfg";
  $spooler->{homedir} = $cwd . "/" . "data";
  $spooler->{cachefile} = $spooler->{homedir} . "/test.cache";
  $spooler->{debug} = 1;
  $spooler->read_config();
  $spooler->prepare_logger();
  unlink($spooler->{cachefile});
  $spooler->{cache}->prep();
  return $spooler->{cache};
}

sub test_logger {
  # Test logging to stdout.
  my $cache = shift;
  $cache->{parent}->{debug} = 1;
  stdout_like { $cache->debug("Test") } qr/^.*: Test/, "debug on ok";
  $cache->{parent}->{debug} = 0;
  stdout_isnt { $cache->debug("Test") } qr/^.*: Test/, "debug off ok";
}

sub test_sql_exec {
  my $cache = shift;
  my @res;
  my $spoolname = "sample-spool-1";

  my $cachefile = $cache->{parent}->{cachefile};
  unlink($cachefile) if (-f $cachefile);
  $cache->prep();

  my $err = "SELECT SOME GOOFY WRONG STUFF";
  throws_ok { $cache->sql_exec($err,()) } qr/could not prepare/,"Syntax error caught ok";

  $err = "SELECT bogus from spools;";
  throws_ok { $cache->sql_exec($err,()) } qr/could not prepare/,"No such column caught ok";

  my $count = "SELECT count(*) from spools";
  @res = $cache->sql_exec($count);
  ok($res[0] == 0,"select count ok");

  my $insert = "INSERT INTO spools (spoolname) VALUES (?)";
  my @args = ($spoolname);
  @res = $cache->sql_exec($insert,@args);
  ok($res[0] = 1,"insert into ok");

  @res = $cache->sql_exec($count);
  my $select = "SELECT complete from spools WHERE spoolname = ?";
  @res = $cache->sql_exec($select,@args);
  ok($res[0] == 0,"select complete ok");
}

sub test_prep_bad_db_path {
  # Test creation of the cache DB.
  my $cache = shift;
  my $cachefile;

  # First ensure failure is caught
  $cache->{parent}->{cachefile} = $cache->{parent}->{homedir} . "/bogus/path/foo";
  $cachefile = $cache->{parent}->{cachefile};
  throws_ok { $cache->prep() } qr/failed to create/, "failure to connect caught";
}

sub test_prep_no_db {
  # Test creation of the cache DB.
  my $cache = shift;
  my $cachefile;

  # Test fetch before prep
  $cache->{dbh}->disconnect();
  $cache->{dbh} = undef;
  throws_ok { $cache->fetch('fake','count') } qr/no database handle/, "no db handle properly caught";
}

sub test_prep_good {
  # Test creation of the cache DB.
  my $cache = shift;
  my $cachefile;

  # Now do it right
  $cache->{parent}->{cachefile} = $cache->{parent}->{homedir} . "/test.cache";
  $cachefile = $cache->{parent}->{cachefile};
  unlink($cachefile) if (-f $cachefile);

  stdout_like { $cache->prep() } qr/creating new cache/, "new cache file correct";
  stdout_like { $cache->prep() } qr/using existing cache/, "existing cache file correct";
  ok(-f $cache->{parent}->{cachefile} == 1,"cache file present ok");
}

sub test_duplicate {
  my $cache = shift;
  # Duplicate insert
  my $spoolname = "sample-spool-1";
  my $insert = "INSERT INTO spools (spoolname) VALUES (?)";
  my @args = ($spoolname);
  # Prepare cache
  $cache->prep();
  # Insert a row
  $cache->sql_exec($insert,@args);
  $cache->sql_exec($insert,@args);
  # Insert the same row and validate it as an error.
  stdout_like { $cache->sql_exec($insert,@args) } qr/failed during execute/, "Duplicate insert caught after 3 tries";
}

sub test_methods {
  my $cache = shift;
  my ($res,@res);
  my $spoolname = "sample-spool-1";

  $cache->{parent}->{cachefile} = $cache->{parent}->{homedir} . "/test.cache";
  my $cachefile = $cache->{parent}->{cachefile};
  $cache->prep();

  $res = $cache->add($spoolname,'count',3);
  $res = $cache->add($spoolname,'time',time());
  @res = $cache->fetch($spoolname,'count');
  ok($res[0] == 3,"sql add count and time ok");
  $cache->counter($spoolname);
  @res = $cache->fetch($spoolname,'count');
  ok($res[0] == 4,"fetch count ok");
  @res = $cache->del($spoolname,'count');
  @res = $cache->fetch($spoolname,'count');
  is($res[0],'',"del and fetch ok");
  $res = $cache->add($spoolname,'count',1);
  $res = $cache->add($spoolname,'complete',0);
  @res = $cache->fetch_complete(0);
  ok($res[0] eq $spoolname,"add and fetch_complete ok");
  $res = $cache->add($spoolname,'complete',1);
  @res = $cache->fetch_complete(0);
  ok($#res == -1,"add and fetch_complete ok");
  @res = $cache->fetch_complete(1);
  ok($res[0] eq $spoolname,"fetch_complete ok");
  @res = $cache->count($spoolname);
  ok($res[0] == 1,"count ok");
  @res = $cache->fetch($spoolname,'time');
  my $time = $res[0];
  @res = $cache->fetch($spoolname,'count',1);
  my @expected = ('sample-spool-1', $time, '1', '1', undef);
  ok(eq_array(\@res, \@expected),"fetch array ok");
  unlink($cache->{parent}->{cachefile});
}

sub test_retry {
  print "test_retry\n";
  # This test loops, and thus runs an indeterminate number
  # of times.  This is why we use done_testing() at the end.
  # We need an LSFSpool object for logger, debug, and config.
  my $spooler = new LSFSpool;
  $spooler->{configfile} = "lsf_spool_good_1.cfg";
  $spooler->{homedir} = $cwd . "/" . "data";
  $spooler->{cachefile} = $spooler->{homedir} . "/test.cache";
  $spooler->{debug} = 0;
  $spooler->read_config();
  $spooler->prepare_logger();

  # now, set cachefile so we cannot connect... see retry happen
  open(DB,">$spooler->{cachefile}");
  close(DB);
  chmod 0000, $spooler->{cachefile};

  my $pid = fork();
  if ($pid) {
    # parent
    # Sleep a little, letting the child fail to prep()
    # Then chmod the cache and ensure child succeeds.
    my $status;
    sleep(3);
    chmod 0644, $spooler->{cachefile};
    while (my $kid = waitpid($pid,0) > 0) {
      $status->{$pid} = $? >> 8;
    }
    ok($status->{$pid} == 0, "prep exits 0 ok");
    unlink($spooler->{cachefile});
    return;
  } else {
    # child
    # This should retry until the chmod above allows it to succeed
    # This should exit 0, but dont' test with lives_ok because in
    # a loop we don't know how many times it'll run, which screws
    # up the test plan.
    $spooler->{cache}->prep();
    # child should exit.
    exit;
  }
}

sub test_retry_fail {
  print "test_retry_fail\n";
  # This test loops, and thus runs an indeterminate number
  # of times.  This is why we use done_testing() at the end.
  # use POSIX qw(:sys_wait_h);
  # We need an LSFSpool object for logger, debug, and config.
  my $spooler = new LSFSpool;
  $spooler->{configfile} = "lsf_spool_good_3.cfg";
  $spooler->{homedir} = $cwd . "/" . "data";
  $spooler->{cachefile} = $spooler->{homedir} . "/test.cache";
  $spooler->{debug} = 0;
  $spooler->read_config();
  $spooler->prepare_logger();

  # now, set cachefile so we cannot connect... see retry happen
  open(DB,">$spooler->{cachefile}");
  close(DB);
  chmod 0000, $spooler->{cachefile};

  my $pid = fork();
  if ($pid) {
    # I'm the parent
    my $status;
    while (my $kid = waitpid($pid,0) > 0) {
      $status->{$pid} = $? >> 8;
    }
    ok( $status->{$pid} > 0,"prep exits > 0 ok");
    unlink($spooler->{cachefile});
    return;
  } else {
    # I'm the kid
    # This should throw an exception.
    # Don't catch it with throws_ok because in a loop we don't
    # know how many times N it'll run, which screws up the test plan.
    $spooler->{cache}->prep();
    exit $?;
  }
}

my $cache = test_start();
test_sql_exec($cache);
test_prep_bad_db_path($cache);
test_prep_no_db($cache);
test_prep_good($cache);
test_logger($cache);
test_duplicate($cache);
test_methods($cache);
test_retry();
test_retry_fail();
