
package DiskUsage::TestSuite;

my $CLASS = __PACKAGE__;

# Standard modules for my unit test suites
use base 'Test::Builder::Module';

use strict;
use warnings;

# Modules for calling this unit test script
use Getopt::Std;
use Error;
use Class::MOP;
use Data::Dumper;
use Cwd;
use File::Basename;
use File::Path;

# Unit test modules
use Test::More tests => 11;
use Test::Output;
use Test::Exception;

# The module to test
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

# Set up common items for this module we're testing.
sub test_start {
  my $self = shift;
  # Instantiate an object to test.
  my $obj = new DiskUsage;
  $obj->parse_args();
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{debug} = 0;
  $obj->{dryrun} = 0;
  $obj->prepare_logger();
  $obj->read_config();
  #print Dumper($obj);
  return $obj;
}

sub test_prepare_logger {
  my $self = shift;
  my $obj = new DiskUsage;
  $obj->{debug} = 1;
  throws_ok { $obj->logger("Test\n"); } qr/no logfile defined/, "missing log check ok";
  $obj->prepare_logger();
  # Test prepare_logger, printing to STDOUT.
  $obj->{debug} = 1;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug on ok";
  stdout_like { $obj->local_debug("Test") } qr/^.*: Test/, "debug on ok";
  $obj->{debug} = 0;
  stdout_like { $obj->logger("Test") } qr/^.*: Test/, "logger with debug off ok";
  stdout_unlike { $obj->local_debug("Test") } qr/^.*: Test/, "debug off ok";
}

sub test_read_good_config_001 {
  my $self = shift;
  # Test a valid config.
  my $obj = new DiskUsage;
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->read_config();
  $obj->prepare_logger();
  is($obj->{config}->{db_tries},5);
}

sub test_read_bad_config_001 {
  my $self = shift;
  my $obj = test_start();
  # Test an invalid config.
  $obj->{configfile} = "$cwd/data/disk_usage_bad_001.cfg";
  throws_ok { $obj->read_config } qr/^error loading.*/, "bad config caught ok";
}

sub test_parse_disk_conf {
  my $self = shift;
  my $obj = test_start();
  $obj->{diskconf} = "$cwd/data/good_disk_conf_001";
  my $hosts = $obj->parse_disk_conf();
  ok(scalar keys %$hosts == 36);

  $obj->{diskconf} = "$cwd/data/good_gscmnt_001";
  $hosts = $obj->parse_disk_conf();
  ok(scalar keys %$hosts == 33);
}

sub test_query_snmp {
  my $self = shift;
  my $obj = test_start();
  # FIXME: need a real SNMP using NFS server to hit
  my $host = "nfs17"; # no vols
  my $result = $obj->{snmp}->query_snmp($host);
  ok(scalar keys %$result > 1);
}

sub test_is_current {
  my $obj = test_start();
  my $host = 'nfs17';
  my $result;
  $obj->{cache}->prep();
  $result = $obj->{snmp}->query_snmp($host);
  $result = $obj->cache($host,$result,0);
  $result = $obj->is_current($host);
  ok($result == 1);
}

sub test_cumulative {
  my $obj = test_start();
  my $host = 'nfs8';
  my $result;
  $obj->{cache}->prep();
  if (! -s $obj->{cachefile}) {
    $result = $obj->{snmp}->query_snmp($host);
    $result = $obj->cache($host,$result);
  }
  $result = $obj->cumulative();
}

sub test_group_totals {
  my $obj = test_start();
  my $host = 'nfs8';
  my $result;
  $obj->{cache}->prep();
  if (! -s $obj->{cachefile}) {
    $result = $obj->{snmp}->query_snmp($host);
    $result = $obj->cache($host,$result);
  }
  $result = $obj->group_totals();
}

# --- end of test subs

sub main {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('DiskUsage::TestSuite');
  foreach my $method ($meta->get_all_methods()) {
    if ($method->name =~ m/^test_/) {
      my $test = $method->name;
      $self->$test();
    }
  }
}

# MAIN
my $opts = {};
getopts("lL",$opts) or
  throw Error::Simple("failure parsing options: $!");

my $Test = $CLASS->new();

# Run "live tests" that actually bsub.
if ($opts->{'L'}) {
  $Test->{live} = 0;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('DiskUsage::TestSuite');
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
