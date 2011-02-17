
package DiskUsage::RRD::TestSuite;

# Standard modules for my unit test suites
use base 'Test::Builder::Module';

use strict;
use warnings;

# Modules for calling this unit test script
use Class::MOP;
use Data::Dumper;
use Cwd qw/abs_path/;
use File::Basename qw/dirname/;

# Unit test modules
use Test::More;
use Test::Output;
use Test::Exception;

# The module to test
use DiskUsage;

my $count = 0;
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
  $obj->{diskconf} = "$cwd/data/good_disk_conf_001";
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = "$cwd/data/test.cache";
  $obj->{debug} = $self->{debug};
  $obj->{rrdpath} = "$cwd/data";
  #$obj->read_config();
  $obj->prepare_logger();
  unlink($obj->{cachefile});
  $obj->{cache}->prep();
  return $obj->{rrd};
}

sub test_fake_rrd {
  my $self = shift;
  my $obj = $self->test_start();
  my $rrdfile = "./t/data/fake.rrd";
  my $rrd = RRDTool::OO->new(
    file => $rrdfile,
  );
  $obj->prep_fake_rrd($rrd);
  ok( $rrd->last() == 1297490400, "fake rrd creation ok");
  unlink $rrdfile;
  unlink $obj->{parent}->{cachefile};
  $count+=1;
}

sub test_run {
  my $self = shift;
  my $obj = $self->test_start();

  # Duplicate insert
  my $params1 = {
    'physical_path' => "/vol/sata801",
    'mount_path' => "/gscmnt/sata801",
    'total_kb' => 1000,
    'used_kb' => 900,
    'group_name' => 'DISK_TEST1',
  };
  my $params2 = {
    'physical_path' => "/vol/sata802",
    'mount_path' => "/gscmnt/sata802",
    'total_kb' => 21000,
    'used_kb' => 2900,
    'group_name' => 'DISK_TEST2',
  };
  # Prepare cache
  my $res = $obj->{parent}->{cache}->prep();
  $res = $obj->{parent}->{cache}->disk_df_add($params1);
  $res = $obj->{parent}->{cache}->disk_df_add($params2);

  lives_ok{ $obj->run() } "test run: runs ok";
  unlink $obj->{parent}->{cachefile};
  unlink("t/data/disk_test1.rrd");
  unlink("t/data/disk_test2.rrd");
  unlink("t/data/total.rrd");
  $count+=1;
}


# --- end of test subs

sub main {
  my $self = shift;
  my $test = shift;
  if (defined $test) {
    print "Run $test\n";
    $self->$test();
  } else {
    my $meta = Class::MOP::Class->initialize('DiskUsage::RRD::TestSuite');
    foreach my $method ($meta->get_method_list()) {
      if ($method =~ m/^test_/) {
        $self->$method();
      }
    }
  }
  done_testing($count);
}

1;

package main;

use Getopt::Std;
use Class::MOP;

# MAIN
my $opts = {};
getopts("dlL",$opts) or
  die "failure parsing options: $!";

my $Test = DiskUsage::RRD::TestSuite->new();

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
    $Test->main($test);
  } else {
    print "No test $test known\n";
  }
} else {
  print "run all tests\n";
  $Test->main();
}
