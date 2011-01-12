# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 10;
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
  $obj->{debug} = 0;
  $obj->prepare_logger();
  return $obj;
}

sub test_logger {
  my $obj = shift;
  $obj->{configfile} = $cwd . "/data/lsf_spool_good_wublast_1.cfg";
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

sub test_activate_suite {
  # test activate suite, the WUBLASTX one.
  my $obj = shift;
  $obj->{debug} = 1;
  my $dir = $cwd . "/data";
  my $file = "sample-wublast-1-1";
  my $path = $dir . "/" . $file;
  $obj->{configfile} = $cwd . "/data/lsf_spool_good_wublast_1.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"WUBLASTX","blast selected ok");
  my $res = $obj->{suite}->action($dir,$path);
  print "Would bsub: $res\n";
  like($res,qr/blastx/,"program is blastx");
  throws_ok { $obj->{suite}->action("bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";
  # FIXME: haven't run yet!
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true ok");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false ok");
}

my $obj = test_start();
test_logger($obj);
test_activate_suite($obj);
