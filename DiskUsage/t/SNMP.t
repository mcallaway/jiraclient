
package DiskUsage::SNMP::TestSuite;

my $CLASS = __PACKAGE__;

# Standard modules for my unit test suites
# use base 'Test::Builder::Module';

use strict;
use warnings;

use Test::More tests => 3;
use Test::Output;
use Test::Exception;

use Class::MOP;
use Getopt::Std;
use Data::Dumper;
use Cwd;
use File::Basename;

use DiskUsage;
use DiskUsage::SNMP;

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

# Determine if we're 'live' and can use LSF.
sub new {
  my $class = shift;
  my $self = {
    live => 1,
  };
  return bless $self, $class;
}

sub test_start {
  my $obj = new DiskUsage;
  $obj->{configfile} = $cwd . "/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = $cwd . "/data/test.cache";
  $obj->{debug} = 0;
  $obj->prepare_logger();
  #$obj->read_config();
  $obj->{diskconf} = "./t/data/good_disk_conf_001";
  $obj->{cachefile} = "./t/data/test.cache";
  unlink($obj->{cachefile});
  $obj->{cache}->prep();
  return $obj;
}

sub test_logger {
  # Test logging to stdout.
  my $obj = test_start();
  $obj->{debug} = 1;
  stdout_like { $obj->local_debug("Test") } qr/^.*: Test/, "test_logger: debug on ok";
  $obj->{debug} = 0;
  stdout_isnt { $obj->local_debug("Test") } qr/^.*: Test/, "test_logger: debug off ok";
}

sub test_cache_snmp {
  my $obj = test_start();
  # Requires active network access to real host
  my $result = $obj->{snmp}->query_snmp('nfs17');
  lives_ok { $obj->cache($result); } "cache_snmp: doesn't crash";
}

# -- end test subs

sub main {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('DiskUsage::SNMP::TestSuite');
  #foreach my $method ($meta->get_all_methods()) {
  foreach my $method ($meta->get_method_list()) {
    #if ($method->name =~ m/^test_/) {
    if ($method =~ m/^test_/) {
      #my $test = $method->name;
      $self->$method();
    }
  }
}

# MAIN
my $opts = {};
getopts("lL",$opts) or
  die("failure parsing options: $!");

my $Test = $CLASS->new();

# Run "live tests" that actually bsub.
if ($opts->{'L'}) {
  $Test->{live} = 0;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('DiskUsage::SNMP::TestSuite');
  #foreach my $method ($meta->get_all_methods()) {
  foreach my $method ($meta->get_method_list()) {
    #if ($method->name =~ m/^test_/) {
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

