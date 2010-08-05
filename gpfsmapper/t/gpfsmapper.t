
package gpfsmapper::TestSuite;

my $CLASS = __PACKAGE__;

# Standard modules for my unit test suites
use base 'Test::Builder::Module';

use strict;
use warnings;

use Data::Dumper;
use Cwd;
use File::Basename;

use Test::More tests => 7;
use Test::Output;
use Test::Exception;

# The module to test
require gpfsmapper;

my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

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
  my $obj = gpfsmapper->new();
  $obj->{config} = "$cwd/data/config_good_001.cfg";
  $obj->{debug} = 1;
  $obj->{dryrun} = 0;
  $obj->read_config();
  return $obj;
}

sub test_read_good_config {
  my $self = shift;
  # Test a valid config.
  my $obj = new gpfsmapper;
  $obj->{config} = "$cwd/data/config_good_001.cfg";
  lives_ok { $obj->read_config() } "read_config 001 ok";
  $obj->{config} = "$cwd/data/config_good_002.cfg";
  lives_ok { $obj->read_config() } "read_config 002 ok";
}

sub test_read_bad_config {
  my $self = shift;
  my $obj = test_start();
  # Test an invalid config.
  $obj->{config} = undef;
  throws_ok { $obj->read_config() } qr/^configuration file not defined/, "undef config caught ok";
  $obj->{config} = "$cwd/data/config_bad_001.cfg";
  throws_ok { $obj->read_config() } qr/^configuration file is empty/, "empty config caught ok";
  $obj->{config} = "$cwd/data/config_bad_002.cfg";
  throws_ok { $obj->read_config() } qr/^failed to parse config/, "bad keys in config caught ok";
  $obj->{config} = "$cwd/data/config_bad_003.cfg";
  throws_ok { $obj->read_config() } qr/^configuration file is empty/, "empty config caught ok";
}

sub test_read_multipath_conf {
  my $self = shift;
  my $obj = test_start();
  $obj->{mpconfig} = "$cwd/data/good_multipath_conf_001";
  lives_ok { $obj->read_multipath_conf(); } "read_multipath_conf ok";
}

# --- end of test subs

sub run {
  my $self = shift;
  my $meta = Class::MOP::Class->initialize('gpfsmapper::TestSuite');
  foreach my $method ($meta->get_all_methods()) {
    if ($method->name =~ m/^test_/) {
      my $test = $method->name;
      $self->$test();
    }
  }
}

package main;

use English qw/$PROGRAM_NAME/;
use Getopt::Std;
use Class::MOP;

exit if ($PROGRAM_NAME ne __FILE__);

# MAIN
my $opts = {};
getopts("lL",$opts) or
  die ("failure parsing options: $!");

my $Test = $CLASS->new();

# Run "live tests" that actually bsub.
if ($opts->{'L'}) {
  $Test->{live} = 0;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('gpfsmapper::TestSuite');
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
  $Test->run();
}

