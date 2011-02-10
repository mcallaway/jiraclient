
package DiskUsage::RRD::TestSuite;

my $CLASS = __PACKAGE__;

# Standard modules for my unit test suites
use base 'Test::Builder::Module';

use strict;
use warnings;

# Modules for calling this unit test script
use Class::MOP;
use Getopt::Std;
use Error;
use Data::Dumper;
use Cwd;
use File::Basename;
use File::Path;

# Unit test modules
use Test::More tests => 2;
use Test::Output;
use Test::Exception;

# The module to test
use DiskUsage;

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub new {
  my $class = shift;
  # Determine if we're 'live' and can connect over the network.
  my $self = {
    live => 0,
    debug => 0,
  };
  return bless $self, $class;
}

# Set up common items for this module we're testing.
sub test_start {
  my $self = shift;
  my $obj = new DiskUsage;
  $obj->{configfile} = $cwd . "/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = $cwd . "/data/test.cache";
  $obj->{debug} = $self->{debug};
  #$obj->read_config();
  $obj->{diskconf} = "./t/data/good_disk_conf_001";
  $obj->{cachefile} = "./t/data/test.cache";
  $obj->{rrdpath} = "./t/data";
  $obj->prepare_logger();  unlink($obj->{cachefile});
  $obj->{cache}->prep();
  return $obj->{rrd};
}

sub test_fake_rrd {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{debug} = 1;
  my $rrdfile = "./t/data/fake.rrd";
  my $rrd = RRDTool::OO->new(
    file => $rrdfile,
  );
  $obj->prep_fake_rrd($rrd);
  ok( $rrd->last() == 1297404000, "fake rrd creation ok");
  unlink $rrdfile;
}

sub test_run {
  my $self = shift;
  my $obj = $self->test_start();
  my $rrdfile = "./t/data/fake.rrd";
  my $rrd = RRDTool::OO->new(
    file => $rrdfile,
  );

  # Duplicate insert
  my $params = {
    'physical_path' => "/vol/sata800",
    'mount_path' => "/gscmnt/sata800",
    'total_kb' => 1000,
    'used_kb' => 900,
    'group_name' => 'DISK_TEST',
  };
  # Prepare cache
  my $res = $obj->{parent}->{cache}->prep();
  $res = $obj->{parent}->{cache}->disk_df_add($params);

  $obj->run();
  lives_ok{ $obj->run() } "test run: runs ok";
  unlink $obj->{parent}->{cachefile};
  unlink $rrdfile;
}


# --- end of test subs

sub main {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('DiskUsage::RRD::TestSuite');
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

# MAIN
my $opts = {};
getopts("dlL",$opts) or
  throw Error::Simple("failure parsing options: $!");

my $Test = $CLASS->new();

if ($opts->{'L'}) {
  $Test->{live} = 1;
}

if ($opts->{'d'}) {
  $Test->{debug} = 1;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('DiskUsage::RRD::TestSuite');
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
