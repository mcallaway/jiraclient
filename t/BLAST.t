# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 15;
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
  $obj->{configfile} = "lsf_spool_good_1.cfg";
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

sub test_count_query {
  # test activate suite, the BLAST one.
  my $obj = shift;
  my $dir = $obj->{homedir};
  my $file = $dir . "/blast-spool-1-1";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();
  ok($obj->{suite}->count_query(">",$file) == 10);
  $file = $dir . "/blast-spool-1-1-output";
  ok($obj->{suite}->count_query("Query=",$file) == 10);

  chmod 0000,$file or die "Failed to set mode to 0000\n";;
  throws_ok { $obj->{suite}->count_query("Query=",$file); } qr/can't open/, "exception ok";
  chmod 0644,$file or die "Failed to reset mode to 0644\n";
}

sub test_activate_suite {
  # test activate suite, the BLAST one.
  my $obj = shift;
  my $dir = $obj->{homedir};
  my $file = "blast-spool-1-1";
  my $path = $dir . "/" . $file;
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();
  is($obj->{config}->{suite}->{name},"BLAST","blast selected ok");
  my $params = $obj->{config}->{suite}->{parameters};
  my $res = $obj->{suite}->action($params,$dir,$path);

  like($res,qr/blastx/,"program is blastx");
  throws_ok { $obj->{suite}->action($params,"bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";
  throws_ok { $obj->{suite}->action($params,$dir,"bogusfile") } qr/^given input file is not a file/, "bad spool file caught correctly";
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true ok");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false ok");
  $file = "blast-spool-1-2";
  ok($obj->{suite}->is_complete("$dir/$file") == 0,"is_complete returns false ok");
}

my $obj = test_start();
test_logger($obj);
test_count_query($obj);
test_activate_suite($obj);
