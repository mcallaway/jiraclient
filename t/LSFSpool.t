
package LSFSpool::TestSuite;

my $CLASS = __PACKAGE__;

use base 'Test::Builder::Module';

use strict;
use warnings;

use Getopt::Std;
use Error;
use Class::MOP;

use Test::More tests => 47;
use Test::Output;
use Test::Exception;

use Data::Dumper;
use Cwd;
use File::Basename;

use LSFSpool;

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub new {
  my $class = shift;
  my $self = {};
  return bless $self, $class;
}

sub test_start {
  my $self = shift;
  # Instantiate an LSFSpool object to test.
  my $obj = new LSFSpool;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->{debug} = 0;
  $obj->{dryrun} = 0;
  $obj->read_config();
  $obj->prepare_logger();
  return $obj;
}

sub test_prepare_logger {
  my $self = shift;
  my $obj = new LSFSpool;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{debug} = 0;
  throws_ok { $obj->logger("Test\n"); } qr/no logfile defined/, "missing log check ok";
  $obj->prepare_logger();
  # Test prepare_logger, printing to STDOUT.
  $obj->{debug} = 1;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug on ok";
  stdout_like { $obj->debug("Test") } qr/^.*: Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug off ok";
  stdout_unlike { $obj->debug("Test") } qr/^.*: Test/, "debug off ok";
  $obj->DESTROY();
}

sub test_read_good_config_1 {
  my $self = shift;
  # Test a valid config.
  my $obj = new LSFSpool;
  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->prepare_logger();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
  $obj->DESTROY();
}

sub test_read_good_config_2 {
  my $self = shift;
  # Test a another valid config.
  my $obj = test_start();
  $obj->{configfile} = "lsf_spool_good_2.cfg";
  $obj->read_config();
  is($obj->{config}->{queue},"backfill");
  ok($obj->{config}->{sleepval} == 60);
  ok($obj->{config}->{queueceiling} == 10000);
  ok($obj->{config}->{queuefloor} == 1000);
  ok($obj->{config}->{churnrate} == 30);
  ok($obj->{config}->{lsf_tries} == 2);
  ok($obj->{config}->{db_tries} == 5);
  $obj->DESTROY();
}

sub test_read_bad_config {
  my $self = shift;
  my $obj = test_start();
  # Test an invalid config.
  $obj->{configfile} = "lsf_spool_bad.cfg";
  throws_ok { $obj->read_config } qr/^error loading.*/, "bad config caught ok";
  $obj->DESTROY();
}

sub test_parsefile {
  my $self = shift;
  my $obj = test_start();

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
  $obj->DESTROY();
}

sub test_parsedir {
  my $self = shift;
  my $obj = test_start();
  $obj->{debug} = 0;

  my $dir = $obj->{homedir} . "/spool/sample-fasta-1";
  my @res = $obj->parsedir($dir);
  ok($res[0] eq $cwd . '/data/spool/sample-fasta-1',"dir ok");
  ok($res[1] eq 'sample-fasta-1-\\$LSB_JOBINDEX',"query ok");
  ok($res[2] eq 'sample-fasta-1[1-2]',"job array ok");
  $dir = $obj->{homedir} . "/spool/sample-fasta-2";
  throws_ok { @res = $obj->parsedir($dir); } qr/spool.*contains no files/, "empty spool caught ok";
  $obj->DESTROY();
}

sub test_bsub {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{debug} = 0;
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
  my $self = shift;
  my $obj = test_start();
  $obj->{debug} = 0;
  $obj->{dryrun} = 1;
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $obj->{homedir} . "/spool/sample-fasta-1";
  my $res = $obj->check_cwd($dir);
  ok($res  == 1);
  $dir = $obj->{homedir} . "/spool";
  throws_ok { $obj->check_cwd($dir); } qr/spool directory has unexpected/, "spotted bad spool ok";
  $obj->DESTROY();
}

sub test_find_progs {
  my $self = shift;
  # Test the find_progs() subroutine.
  my $obj = test_start();
  ok($obj->find_progs() == 0);
  like($obj->{bsub},qr/^.*\/bsub/,"bsub is found");
  like($obj->{bqueues},qr/^.*\/bqueues/,"bqueues is found");
  $obj->DESTROY();
}

sub test_finddirs {
  my $self = shift;
  my $obj = test_start();
  my $dir = $obj->{homedir};
  my @res = $obj->finddirs($dir);
  lives_ok { $obj->finddirs($dir); } "finddirs lives ok";
  $obj->DESTROY();
}

sub test_findfiles {
  my $self = shift;
  my $obj = test_start();
  my $dir = $obj->{homedir};
  lives_ok { $obj->findfiles($dir); } "findfiles lives ok";
  $obj->DESTROY();
}

sub test_build_cache {
  my $self = shift;
  # Test cache building.
  my @res;
  my $obj = new LSFSpool;

  $obj->{homedir} = $cwd . "/" . "data";
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->{debug} = 0;
  $obj->{buildonly} = 1;
  $obj->prepare_logger();
  $obj->read_config();
  $obj->activate_suite();

  my $dir = $obj->{homedir} . "/" . "spool/sample-fasta-1";
  $obj->build_cache($dir);

  @res = $obj->{cache}->fetch($dir,'count');
  ok($res[0] == 0,"'count' is correctly 0");
  @res = $obj->{cache}->fetch_complete(0);
  ok($res[0] eq $dir,"'fetch_complete' correctly fetches dir");
  @res = $obj->{cache}->fetch($dir,'spoolname');
  ok($res[0] eq $dir,"'spoolname' is correct");
  unlink($obj->{cachefile});
}

sub test_activate_suite {
  my $self = shift;
  # test activate suite, the trivial one.
  my $obj = $self->test_start();
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
}

sub main {
  my $self = shift;
  $self->test_prepare_logger();
  $self->test_parsefile();
  $self->test_parsedir();
  $self->test_bsub();
  $self->test_finddirs();
  $self->test_findfiles();
  $self->test_check_cwd();
  $self->test_find_progs();
  $self->test_read_good_config_1();
  $self->test_read_good_config_2();
  $self->test_read_bad_config();
  $self->test_activate_suite();
  $self->test_build_cache();
}

# MAIN
my $opts = {};
getopts("l",$opts) or
  throw Error::Simple("failure parsing options: $!");

my $Test = $CLASS->new();

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('LSFSpool::TestSuite');
  foreach my $method ($meta->get_all_methods()) {
    if ($method->name =~ m/^test_/) {
      print $method->name . "\n";
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

1;
