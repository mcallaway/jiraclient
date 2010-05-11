# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 16;
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Cwd;
use File::Basename;

BEGIN { use_ok('LSFSpool') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub test_start {
  # Instantiate an LSFSpool object to test.
  my $obj = new LSFSpool;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{debug} = 1;
  $obj->prepare_logger();
  return $obj;
}

sub test_logger {
  my $obj = shift;
  $obj->{configfile} = "lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  $obj->{debug} = 1;
  stdout_like { $obj->{suite}->logger("Test\n"); } qr/Test/, "logger with debug on ok";
  stdout_like { $obj->{suite}->debug("Test\n"); } qr/Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->{suite}->logger("Test\n"); } qr/Test/, "logger with debug off ok";
  $obj->{suite}->debug("Test\n");
  stdout_unlike { $obj->{suite}->debug("Test\n"); } qr/Test/, "debug off ok";
}

sub test_run {
  my $obj = shift;
  $obj->{configfile} = "lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"Trivial");
  throws_ok { $obj->{suite}->run("BOGUS") } qr/^failed to exec/, "bad command caught ok";
  ok($obj->{suite}->run("/bin/ls") == 0,"'/bin/ls' command exits 0 ok");
  throws_ok { $obj->{suite}->run("/bin/false") } qr/command exits non-zero/, "'/bin/false' command exits 1 ok";
}

sub test_activate_suite {
  # test activate suite, the trivial one.
  my $obj = shift;
  my $dir = $obj->{homedir} . "/" . "spool/sample-fasta-1";
  my $file = "sample-fasta-1-1";
  $obj->{configfile} = "lsf_spool_trivial.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"Trivial");
  $obj->{suite}->action($dir,$file);
  ok(-f "$dir/$file-output" == 1,"file is present");
  throws_ok { $obj->{suite}->action("bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";
  throws_ok { $obj->{suite}->action($dir,"bogusfile") } qr/^given input file is not a file/, "bad spool file caught correctly";
  stdout_like { $obj->{suite}->logger("test\n") } qr/test/, "stdout logs 'test' ok";
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false");
}

my $obj = test_start();
test_logger($obj);
test_run($obj);
test_activate_suite($obj);
