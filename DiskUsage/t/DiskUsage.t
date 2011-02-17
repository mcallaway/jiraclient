
package DiskUsage::TestSuite;

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
use Log::Log4perl qw/:levels/;

# Unit test modules
use Test::More tests => 8;
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
  # Instantiate an object to test.
  my $obj = new DiskUsage;
  $obj->parse_args();
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{debug} = $self->{debug};
  $obj->{dryrun} = 0;
  $obj->prepare_logger();
  $obj->{diskconf} = "./t/data/good_disk_conf_001";
  $obj->{cachefile} = "./t/data/test.cache";
  return $obj;
}

sub test_prepare_logger {
  my $self = shift;
  my $obj = new DiskUsage;
  throws_ok { $obj->{logger}->warn("Test\n"); } qr/Can't call method/, "missing log check ok";
  $obj->prepare_logger();

  # Test prepare_logger, printing to STDOUT.
  $obj->{logger}->level($DEBUG);
  stderr_like { $obj->{logger}->error("Test") } qr/^.* Test/, "properly see error";
  stderr_like { $obj->{logger}->debug("Test") } qr/^.* Test/, "properly see debug";
  $obj->{logger}->level($WARN);
  stderr_like { $obj->{logger}->error("Test") } qr/^.* Test/, "logger with debug off ok";
  stderr_unlike { $obj->{logger}->debug("Test") } qr/^.* Test/, "debug off ok";
}

sub test_parse_disk_conf {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{diskconf} = "$cwd/data/good_disk_conf_001";
  my $hosts = $obj->parse_disk_conf();
  ok(scalar keys %$hosts == 36);

  $obj->{diskconf} = "$cwd/data/good_gscmnt_001";
  $hosts = $obj->parse_disk_conf();
  ok(scalar keys %$hosts == 33);
}

sub test_define_hosts {
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{diskconf} = "$cwd/data/good_gscmnt_001";
  $obj->{hosts} = "host1,host2";
  my $hosts = $obj->define_hosts();
  ok(scalar keys %$hosts == 35);
}

sub test_update_cache {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  $obj->{force} = 1;
  my $hosts = { 'nfs17'=>{} };
  lives_ok { $obj->update_cache($hosts); } "update_cache runs ok";
}

sub test_query_snmp {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  $obj->{cache}->prep();
  my $host = "nfs24";
  my $result = $obj->{snmp}->query_snmp($host);
  ok(scalar keys %$result > 1);
}

sub test_cache_result {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  $obj->{cache}->prep();
  my $host = "nfs17";
  my $result = $obj->{snmp}->query_snmp($host);
  ok(scalar keys %$result > 1);
  my $error = 0;
  my $res = $obj->cache($host,$result,$error);
}

sub test_is_current {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  my $host = 'nfs17';
  my $result;
  $obj->{cache}->prep();
  $result = $obj->{snmp}->query_snmp($host);
  $result = $obj->cache($host,$result,0);
  $result = $obj->is_current($host);
  ok($result == 1);
}

# --- end of test subs

sub main {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('DiskUsage::TestSuite');
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
  my $meta = Class::MOP::Class->initialize('DiskUsage::TestSuite');
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

1;
