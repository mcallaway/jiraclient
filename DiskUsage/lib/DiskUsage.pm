
package DiskUsage;

use strict;
use warnings;

# Use Dumper for debugging
use Data::Dumper;
# Parse CLI options
use Getopt::Std;
# Use try/catch exceptions
use Exception::Class::TryCatch;
# Checking currentness in is_current()
use Date::Manip;
# Usage function
use Pod::Find qw(pod_where);
use Pod::Usage;

use DiskUsage::Error;
use DiskUsage::Cache;
use DiskUsage::SNMP;

# Autoflush
local $| = 1;

our $VERSION = "0.0.1";

# Add commas to big numbers
my $comma_rx = qr/\d{1,3}(?=(\d{3})+(?!\d))/;
# Convention for all NFS exports
my @prefixes = ("/vol","/home");
# Input file for all filer hosts
#my $config = "disk.conf";
#my $config = "srv";

# A mapping of disk related OIDs
my $oids = {
  'hrStorageEntry' => '1.3.6.1.2.1.25.2.3.1.0',
  'hrStorageIndex' => '1.3.6.1.2.1.25.2.3.1.1',
  'hrStorageType'  => '1.3.6.1.2.1.25.2.3.1.2',
  'hrStorageDescr' => '1.3.6.1.2.1.25.2.3.1.3',
  'hrStorageAllocationUnits' => '1.3.6.1.2.1.25.2.3.1.4',
  'hrStorageSize'  => '1.3.6.1.2.1.25.2.3.1.5',
  'hrStorageUsed'  => '1.3.6.1.2.1.25.2.3.1.6',
  'extOutput'      => '1.3.6.1.4.1.2021.8.1.101.1',
};

sub new {
  my $self = {
    debug => 0,
    maxage => 1, # hours : FIXME, add to config file
    configfile => undef,
    cachefile => undef,
    logdir => undef,
    logfile => undef,
    logfh => undef,
    dbh => undef,
    diskconf => "./disk.conf",
    cache => new DiskUsage::Cache,
    snmp => new DiskUsage::SNMP,
    config  => {},
  };
  bless $self, 'DiskUsage';
  $self->{cache}->{parent} = $self;
  $self->{snmp}->{parent} = $self;
  # This is a bit of a hack to get sub-modules to use the
  # same logging/debugging as the toplevel module.  Should probably
  # have a Utility library or something.
  return $self;
}

sub error {  # Raise a generic Exception object.
  my $self = shift;
  $self->logger("Error: @_");
  DiskUsage::Error->throw( error => @_ );
}

sub logger {
  # Simple logging where logfile is set during startup
  # to either a file handle or STDOUT.
  my $self = shift;
  my $fh = $self->{logfh};

  $self->error("no logfile defined, run prepare_logger\n")
    if (! defined $fh);

  print $fh localtime() . ": @_";
}

sub local_debug {
  # Simple debugging.
  my $self = shift;
  if ($self->{debug}) {
    $self->logger("DEBUG: @_");
  }
}

sub version {
  my $self = shift;
  print "disk_usage $VERSION\n";
}

sub prepare_logger {
  # Set the file handle for the log.
  # Use logfile in .cfg if not given on CLI.
  my $self = shift;
  # Config file may specify a logfile
  if (defined $self->{config}->{logfile}) {
    $self->{logfile} = $self->{config}->{logfile};
  }
  # Command line overrides config file
  if (defined $self->{logfile}) {
    $self->{logfile} = $self->{logfile};
  }
  # Open logfile or STDOUT.
  if (defined $self->{logfile}) {
    open(LOGFILE,">>$self->{logfile}") or
      $self->error("failed to open log file $self->{logfile}: $!\n");
    $self->{logfh} = \*LOGFILE;
  } else {
    $self->{logfh} = \*STDOUT;
  }
}

sub read_config {
  # Read a simple configuration file that contains a hash object
  # and subroutines.
  my $self = shift;

  # abs_path for config file path
  #use File::Basename;
  use Cwd qw/abs_path/;
  # YAML has Load
  use YAML::XS;
  # Slurp has read_file
  use File::Slurp;

  $self->local_debug("read_config()\n");

  return
    if (! defined $self->{configfile});

  $self->error("no such file: $self->{configfile}\n")
    if (! -f $self->{configfile});

  my $configfile = abs_path($self->{configfile});

  $self->{config} = Load scalar read_file($configfile) ||
    $self->error("error loading config file '$configfile': $!\n");

  # Validate configuration, required fields.
  my @required = ( 'db_tries' );
  foreach my $req (@required) {
    $self->error("configuration is missing required parameter '$req'\n")
      if (! exists $self->{config}->{$req});
  }
  foreach my $key (keys %{ $self->{config} } ) {
    $self->{$key} = $self->{config}->{$key}
      if (exists $self->{$key});
  }
}

# Read the config file and find NFS servers and Filters
sub parse_disk_conf {

  my $self = shift;

  $self->local_debug("parse_disk_conf()\n");
  $self->logger("using disk config file: $self->{diskconf}\n");
  $self->error("error loading disk configuration file: $self->{diskconf}: $!\n")
    if (! -f $self->{diskconf});

  # Parse config file for disk definitions.
  open FH, "<", $self->{diskconf} or
    $self->error("Failed to open $self->{diskconf}: $!\n");

  my $result = {};
  my $gscmnt = 0; # sets format to be expected
  while (<FH>) {
    my $host;
    $gscmnt = 1 if (/^#!/);
    next if (/^(#|$)/);

    if ($gscmnt) {
      # This is the automount config
      if (/^\s+echo\s+"(\S+?):/) {
        $host = $1;
        $host =~ s/^(\S+)-\d+/$1/;
        $result->{$host} = {};
      }
      next;
    }

    # Read the disk conf file and create the hosts hash.
    # format: type hostname args...
    if (/^\S+\s+(\S+)\s+.*/) {
      $host = $1;
    } else {
      next;
    }

    # handle hostname-N special case
    $host = substr($host,0,index($host,"-"))
      if (index($host,"-") != -1);

    $result->{$host} = {};
  }
  close(FH);
  $self->local_debug("found " . scalar(keys %$result). " host(s)\n");
  return $result;
}

sub define_hosts {
  # target host may be a CLI arg or come from a config file

  my $self = shift;
  my @argv = @_;
  my $hosts;

  $self->local_debug("define_hosts()\n");

  if ($#argv > -1) {
    my $type = undef;
    foreach my $host (@argv) {
      $hosts->{$host} = {};
    }
  } else {
    $hosts = $self->parse_disk_conf();
  }

  return $hosts;
}

sub cache {
  my $self = shift;
  my $host = shift;
  my $result = shift;
  my $err = shift;

  return if (! defined $host);
  return if (! defined $result);

  $self->local_debug("cache()\n");

  foreach my $key (keys %$result) {
    $self->{cache}->disk_df_add($result->{$key});
  }

  $self->{cache}->disk_hosts_add($host,$result,$err);
}

sub is_current {
  # Look in the cache at last_modified and check if the
  # delta between now and then is less than max age.
  my $self = shift;
  my $host = shift;

  $self->local_debug("is_current()\n");

  return 0 if ($self->{force});

  my $result = $self->{cache}->sql_exec('SELECT last_modified FROM disk_hosts WHERE hostname = ?',($host));
  return 0 if (scalar @$result < 1);

  my $date0 = $result->[0]->[0];
  return 0 if (! defined $date0);

  my @res = split(':',DateCalc($date0,gmtime()));
  my $hours = $res[4];
  return 0 if (! defined $hours);

  $self->local_debug("hrs delta: @res => $hours hrs\n");
  return 1
    if $hours < $self->{maxage};

  return 0;
}

sub parse_args {

  my $self = shift;
  my %opts;

  getopts("cC:dfhi:l:V",\%opts) or
    $self->error("Error parsing options\n");

  if ($opts{'h'}) {
    pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
    exit;
  }
  if ($opts{'V'}) {
    $self->version();
    exit;
  }

  $self->{cacheonly} = delete $opts{'c'} ? 1 : 0;
  $self->{configfile} = delete $opts{'C'};
  $self->{debug} = delete $opts{'d'} ? 1 : 0;
  $self->{force} = delete $opts{'f'} ? 1 : 0;
  $self->{logfile} = delete $opts{'l'};
  $self->{cachefile} = delete $opts{'i'};
}

sub cumulative {
  my $self = shift;
  my $result;
  $result = $self->{cache}->sql_exec("SELECT SUM(total_kb) from disk_df");
  my $total = $result->[0]->[0];
  $result = $self->{cache}->sql_exec("SELECT SUM(used_kb) from disk_df");
  my $used = $result->[0]->[0];
  $self->local_debug("cumulative(): $total $used\n");
  return ($total,$used);
}

sub group_totals {
  my $self = shift;
  my $result;
  $result = $self->{cache}->sql_exec("SELECT group_name,SUM(total_kb),SUM(used_kb) from disk_df GROUP BY group_name");
  return $result;
}

sub build_cache {

  my $self = shift;
  my $hosts = shift;

  $self->local_debug("build_cache()\n");

  $self->{cache}->prep();

  foreach my $host (keys %$hosts) {
    # Have to queried this host recently?
    if (! $self->is_current($host) ) {
      print "Querying host $host\n";
      if (defined $hosts->{$host}) {
        # Query the host and cache the result
        my $result = {};
        my $error = 0;
        try eval {
          $result = $self->{snmp}->query_snmp($host);
        };
        if (catch my $err) {
          $self->logger("snmp error: $host: " . $err->{message});
          $error = 1;
        }
        $self->cache($host,$result,$error);
      }
    }
  } # end foreach my $host
}

sub main {

  my $self = shift;
  my @args = @_;

  # Set auto flush, useful with "tee".
  $| = 1;

  # Parse CLI args
  $self->parse_args();

  # Open log file as soon as we have options parsed.
  $self->prepare_logger();

  # Read configuration file, may have logfile setting in it.
  $self->read_config();

  # Define list of hosts to query
  my $hosts = $self->define_hosts(@ARGV);

  # Build the cache of data
  $self->build_cache($hosts);
  $self->logger("queried " . ( scalar keys %$hosts ) . " host(s)\n");
  return if $self->{cacheonly};

  # Tally totals per disk_group_name and cumulative
  my ($total,$used) = $self->cumulative();
  my $group_totals = $self->group_totals();

}

1;

__END__

=pod

=head1 NAME

DiskUsage - Gather disk consumption data

=head1 SYNOPSIS

  disk_usage [options]

=head1 OPTIONS

 -c         Build the cache only.
 -C [file]  Specify config file.
 -d         Enable debug mode.
 -f         Force refresh.
 -h         This useful documentation.
 -i [file]  Set file path for cache file.
 -l [file]  Set file path for log file.
 -V         Display version.

=head1 DESCRIPTION

This module gathers disk usage information.

=cut
