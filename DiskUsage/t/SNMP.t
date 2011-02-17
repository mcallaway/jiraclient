
package DiskUsage::SNMP::TestSuite;

# Standard modules for my unit test suites
# use base 'Test::Builder::Module';

use strict;
use warnings;

use Test::More;
use Test::Output;
use Test::Exception;

use Class::MOP;
use Data::Dumper;
use Cwd qw/abs_path/;
use File::Basename qw/dirname/;
use Log::Log4perl qw/:levels/;

use DiskUsage;
use DiskUsage::SNMP;

my $count = 0;
my $thisfile = Cwd::abs_path(__FILE__);
my $cwd = dirname $thisfile;

sub new {
  my $class = shift;
  # live means we're on local network and can connect
  my $self = {
    live => 0,
    debug => 0,
  };
  return bless $self, $class;
}

sub test_start {
  my $self = shift;
  my $obj = new DiskUsage;
  $obj->{configfile} = "$cwd/data/disk_usage_good_001.cfg";
  $obj->{cachefile} = "$cwd/data/test.cache";
  $obj->{debug} = $self->{debug};
  $obj->prepare_logger();
  $obj->{diskconf} = "$cwd/data/good_disk_conf_001";
  $obj->{cache}->prep();
  return $obj;
}

sub test_logger {
  # Test logging to stderr.
  my $self = shift;
  my $obj = $self->test_start();
  $obj->{logger}->level($DEBUG);
  stderr_like { $obj->{logger}->debug("Test") } qr/^.* Test/, "test_logger: debug on ok";
  $obj->{logger}->level($WARN);
  stderr_isnt { $obj->{logger}->debug("Test") } qr/^.* Test/, "test_logger: debug off ok";
  unlink $obj->{cachefile};
  $count+=2;
}

sub test_connect {
  my $self = shift;
  my $obj = $self->test_start();
  my $result = {};
  my $host = "foo";
  throws_ok { $obj->{snmp}->connect_snmp($host); } qr/SNMP failed/, "test_connect: fails ok on bad host";
  unlink $obj->{cachefile};
  $count+=1;
}

sub test_snmp_get_table {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  # Only use this test during development when you know
  # we can connect to target host;
  my $host = "gpfs";
  my $res = $obj->{snmp}->connect_snmp($host);
  $res = $obj->{snmp}->snmp_get_table('1.3.6.1.2.1.25.4.2.1.2');
  ok( scalar @{ [ keys %$res ] } > 1, "test snmp_get_table" );
  unlink $obj->{cachefile};
  $count+=1;
}

sub test_snmp_get_request {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  # Only use this test during development when you know
  # we can connect to target host;
  my $host = "nfs17";
  my $res = $obj->{snmp}->connect_snmp($host);
  $res = $obj->{snmp}->snmp_get_request( ['1.3.6.1.2.1.1.1.0', '1.3.6.1.2.1.1.5.0']);
  ok( $res->{ '1.3.6.1.2.1.1.1.0' } =~ /^Linux/, "test_snmp_get_request: nfs17 is linux");
  ok( $res->{ '1.3.6.1.2.1.1.5.0' } eq 'linuscs84', "test_snmp_get_request: sysDesc is linuxcs84");
  unlink $obj->{cachefile};
  $count+=2;
}

sub test_snmp_get_serial_request {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  # Only use this test during development when you know
  # we can connect to target host;
  my $host = "nfs24";
  my $res = $obj->{snmp}->connect_snmp($host);
  my $oid = '1.3.6.1.2.1.25.2.3.1.3';
  $res = $obj->{snmp}->snmp_get_serial_request( $oid );
  #print scalar @{ [ keys %$res ] } . "\n";
  ok( scalar @{ [ keys %$res ] } == 98, "test_snmp_get_serial_request: ok");
  unlink $obj->{cachefile};
  $count+=1;
}

sub test_type_mapper {
  my $self = shift;
  my $obj = $self->test_start();
  my $string = "This is an unrecognized sysDescr string";
  throws_ok { $obj->{snmp}->type_string_to_type($string); } qr/No such host/, "test_type_mapper: fails ok on bad host type";
  $string = "NetApp Release 7.3.2: Thu Oct 15 04:12:15 PDT 2009";
  my $res = $obj->{snmp}->type_string_to_type($string);
  ok($res = 'linux',"test_type_mapper: sees netapp ok");
  unlink $obj->{cachefile};
  $count+=2;
}

sub test_get_host_type {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  my $result = {};

  my $host = "nfs17";
  $obj->{snmp}->connect_snmp($host);
  my $res = $obj->{snmp}->get_host_type($host);
  ok( $res eq 'linux', "test_get_host_type: linux detected" );

  $host = "ntap8";
  $obj->{snmp}->connect_snmp($host);
  $res = $obj->{snmp}->get_host_type($host);
  #print Dumper($res);
  ok( $res eq 'netapp', "test_get_host_type: ntap8 detected" );
  unlink $obj->{cachefile};
  $count+=2;
}

sub test_get_snmp_disk_usage {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  my $result = {};
  my $host = "nfs11";
  $obj->{snmp}->connect_snmp($host);
  $obj->{snmp}->get_snmp_disk_usage($result);
  #print Dumper($result);
  unlink $obj->{cachefile};
  ok( scalar keys %$result > 1, "test_get_snmp_disk_usage: nfs11 ok");

  $host = "ntap8";
  $obj->{snmp}->connect_snmp($host);
  $obj->{snmp}->get_snmp_disk_usage($result);
  #print Dumper($result);
  ok( scalar keys %$result > 1, "test_get_snmp_disk_usage: ntap8 ok");
  unlink $obj->{cachefile};
  $count+=2;
}

sub test_cache_snmp {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  # Requires active network access to real host
  my $host = "nfs24";
  my $err = 0;
  $obj->{snmp}->connect_snmp($host);
  my $result = $obj->{snmp}->query_snmp($host);
  lives_ok { $obj->cache($host,$result,$err); } "cache_snmp: doesn't crash";
  unlink $obj->{cachefile};
  $count+=1;
}

sub test_target {
  my $self = shift;
  return if (! $self->{live});
  my $obj = $self->test_start();
  # Requires active network access to real host
  my $host = "ntap9";
  my $err = 0;
  $obj->{snmp}->connect_snmp($host);
  my $result = $obj->{snmp}->query_snmp($host);
  #print Dumper $result;
  ok( ref $result eq 'HASH', "test target" );
  unlink $obj->{cachefile};
  $count+=1;
}

# -- end test subs

sub main {
  my $self = shift;
  my $test = shift;
  if (defined $test) {
    print "Run $test\n";
    $self->$test();
  } else {
    my $meta = Class::MOP::Class->initialize('DiskUsage::SNMP::TestSuite');
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

use Class::MOP;
use Getopt::Std;

# MAIN
my $opts = {};
getopts("dlL",$opts) or
  die("failure parsing options: $!");

my $Test = DiskUsage::SNMP::TestSuite->new();

if ($opts->{'d'}) {
  $Test->{debug} = 1;
}

# Disable "live tests" that actually connect over the network.
if ($opts->{'L'}) {
  $Test->{live} = 1;
}

if ($opts->{'l'}) {
  print "Display list of tests\n\n";
  my $meta = Class::MOP::Class->initialize('DiskUsage::SNMP::TestSuite');
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

