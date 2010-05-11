# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 45;
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Class::MOP;
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
  throws_ok { $obj->logger("Test\n"); } qr/no logfile defined/, "missing log check ok";
  $obj->prepare_logger();
  return $obj;
}

sub test_prepare_logger {
  # Test prepare_logger, printing to STDOUT.
  my $obj = shift;
  $obj->{debug} = 1;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug on ok";
  stdout_like { $obj->debug("Test") } qr/^.*: Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug off ok";
  stdout_unlike { $obj->debug("Test") } qr/^.*: Test/, "debug off ok";
}

sub test_read_good_config_1 {
  # Test a valid config.
  my $obj = shift;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
}

sub test_read_good_config_2 {
  # Test a another valid config.
  my $obj = shift;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_2.cfg";
  $obj->read_config();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
}

sub test_read_bad_config {
  # Test an invalid config.
  my $obj = shift;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_bad.cfg";
  throws_ok { $obj->read_config } qr/^error loading.*/, "bad config caught ok";
}

sub test_parsefile {
  my $obj = shift;

  my $file = "seq-blast-spool-1-1";
  my $path = $obj->{homedir} . "/" . $file;
  my @res = $obj->parsefile($path);

  $file =~ /^.*-(\d+)/;
  my $base = basename dirname $path;
  my $number = $1;
  my $array = "$base\[$number\]";

  # This is the parent dir of the file
  ok($res[0] eq $obj->{homedir}, "spooldir ok");
  # This is the file
  ok($res[1] eq $file, "inputfile ok");
  # This is the job array: dir + number
  ok($res[2] eq $array, "job array ok");

  $file = "foo";
  $path = $obj->{homedir} . "/" . $file;
  throws_ok { $obj->parsefile($path); } qr/filename does not contain a number/, "bad filename caught ok";
}

sub test_parsedir {
  my $obj = shift;
  $obj->{debug} = 1;

  my $dir = $obj->{homedir} . "/spool/sample-fasta-1";
  my @res = $obj->parsedir($dir);
  ok($res[0] eq '/gscuser/mcallawa/src/LSFSpool/t/data/spool/sample-fasta-1',"dir ok");
  ok($res[1] eq 'sample-fasta-1-\\$LSB_JOBINDEX',"query ok");
  ok($res[2] eq 'sample-fasta-1[1-2]',"job array ok");
}

sub test_bsub {
  my $obj = shift;
  $obj->{debug} = 1;
  $obj->{dryrun} = 1;
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();

  my $file = "sample-fasta-1-1";
  my $dir = $obj->{homedir} . "/spool/sample-fasta-1/";
  my $path = $dir . "/" . $file;
  my $id = $obj->bsub($path);
  ok($id == 0);
}

sub test_check_cwd {
  my $obj = shift;
  $obj->{debug} = 1;
  $obj->{dryrun} = 1;
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $obj->{homedir} . "/spool/sample-fasta-1";
  my $res = $obj->check_cwd($dir);
  ok($res  == 1);
  $dir = $obj->{homedir} . "/spool";
  throws_ok { $obj->check_cwd($dir); } qr/spool directory has unexpected/, "spotted bad spool ok";
}

sub test_find_progs {
  # Test the find_progs() subroutine.
  my $obj = shift;
  ok($obj->find_progs() == 0);
  like($obj->{bsub},qr/^.*\/bsub/,"bsub is found");
  like($obj->{bqueues},qr/^.*\/bqueues/,"bqueues is found");
}


sub test_build_cache {
  # Test cache building.
  my @res;
  my $obj = new LSFSpool;

  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->{debug} = 1;
  $obj->{buildonly} = 1;
  $obj->prepare_logger();
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $obj->{homedir} . "/" . "spool/sample-fasta-1";
  $obj->build_cache($dir);

  @res = $obj->{cache}->fetch($dir,'count');
  ok($res[0] == 0,"'count' is correctly 0");
  @res = $obj->{cache}->fetch_complete(0);
  print Dumper @res;
  ok($res[0] eq $dir,"'fetch_complete' correctly fetches dir");
  @res = $obj->{cache}->fetch($dir,'spoolname');
  ok($res[0] eq $dir,"'spoolname' is correct");
  unlink($obj->{cachefile});
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
  ok(-f "$dir/$file-output" == 1);
  throws_ok { $obj->{suite}->action("bogusdir",$file) } qr/^given spool is not a directory/, "bad spool dir caught correctly";
  throws_ok { $obj->{suite}->action($dir,"bogusfile") } qr/^given input file is not a file/, "bad spool file caught correctly";
  throws_ok { $obj->{suite}->run("BOGUS") } qr/^failed to exec/, "bad command caught correctly";
  ok($obj->{suite}->run("/bin/ls") == 0,"'/bin/ls' command exits 0");
  $obj->{suite}->logger("test\n");
  ok($obj->{suite}->is_complete("$dir/$file") == 1,"is_complete returns true");
  ok($obj->{suite}->is_complete("$dir/bogus") == 0,"is_complete returns false");
  #unlink("$dir/$file-output");
}

my $obj = test_start();
test_prepare_logger($obj);
test_parsefile($obj);
test_parsedir($obj);
test_bsub($obj);
test_check_cwd($obj);
test_find_progs($obj);
test_read_good_config_1($obj);
test_read_good_config_2($obj);
test_read_bad_config($obj);
test_activate_suite($obj);
test_build_cache();
