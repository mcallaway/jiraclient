# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl LSFSpool.t'

#########################

use strict;
use warnings;

use Test::More tests => 12;
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
  $obj->{configfile} = "lsf_spool_good_1.cfg";
  $obj->{dryrun} = 1;
  $obj->prepare_logger();
  $obj->read_config();
  $obj->activate_suite();
  return $obj;
}

sub ostr {
  my $str = shift;
  return split(/ /,$str);
}

sub test_bad_opt {
  my $obj = test_start();
  my $opts = "-n -d -q $cwd/data/spool/sample-fasta-1";
  my $res;
  throws_ok { $res = $obj->main(ostr($opts)); } qr/Error parsing options/, "bad opt caught ok";
  $obj->DESTROY();
}

sub test_help {
  my $obj = test_start();
  my $opts = "-h";
  my $res;
  stdout_like { $res = $obj->main(ostr($opts)); } qr/Usage:/, "usage prints ok";
  ok($res == 0,"help returns 0 ok");
  $obj->DESTROY();
}

sub test_debug_dryrun_opts {
  my $obj = test_start();
  my $opts = "-n -d $cwd/data/spool/sample-fasta-1";
  throws_ok { $obj->main(ostr($opts)); } qr/no action specified/, "no action caught ok";
  $opts = "-n -s -d $cwd/data/spool/sample-fasta-1";
  ok( $obj->{debug} == 1, "debug set ok");
  $obj->{dryrun} = 0;
  $opts = "-n -s -d $cwd/data/spool/sample-fasta-1";
  ok( $obj->main(ostr($opts)) == 0,"test run went ok");
  ok( $obj->{dryrun} == 1,"dryrun set ok");
  $obj->DESTROY();
}

sub test_set_cache {
  my $obj = test_start();
  my $opts = "-i $cwd/data/test.cache -v -d $cwd/data/spool/sample-fasta-1";
  ok($obj->main(ostr($opts)) == 0,"test run went ok");
  ok(-f $obj->{cachefile} == 1,"cache file present ok");
  chmod(0644, $obj->{cachefile});
  $obj->DESTROY();
}

sub test_set_logfile {
  my $obj = test_start();
  my $opts = "-l $cwd/testlog -v -d $cwd/data/spool/sample-fasta-1";
  ok($obj->main(ostr($opts)) == 0,"test run went ok");
  ok(-f $obj->{logfile} == 1,"cache file present ok");
  unlink("$cwd/testlog");
  $obj->DESTROY();
}

# Main
test_bad_opt();
test_help();
test_debug_dryrun_opts();
test_set_cache();
test_set_logfile();
