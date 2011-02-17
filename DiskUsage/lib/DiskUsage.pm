
package DiskUsage;

use strict;
use warnings;

# Use Dumper for debugging
use Data::Dumper;
# Parse CLI options
use Getopt::Std;
# Checking currentness in host_is_current()
use Date::Manip;
# Usage function
use Pod::Find qw(pod_where);
use Pod::Usage;

use DiskUsage::Cache;
use DiskUsage::RRD;
use DiskUsage::SNMP;

# Autoflush
local $| = 1;

our $VERSION = "0.13.0";

sub new {
  my $self = {
    debug      => 0,
    force      => 0,
    db_tries   => 5,
    timeout    => 15,
    host_maxage => 86400, # max seconds since last check
    vol_maxage => 15, # max days since last check
    diskconf   => "./disk.conf",
    configfile => undef,
    cachefile  => "/var/www/domains/gsc.wustl.edu/diskusage/cgi-bin/du.cache",
    rrdpath    => "/var/www/domains/gsc.wustl.edu/diskusage/cgi-bin/rrd",
    logdir     => undef,
    logfile    => undef,
    logfh      => undef,
    dbh        => undef,
    purge      => undef, # max days since last volume update are "aged"
    config     => {},
    cache      => new DiskUsage::Cache,
    snmp       => new DiskUsage::SNMP,
    rrd        => new DiskUsage::RRD,
  };
  bless $self, 'DiskUsage';
  $self->{cache}->{parent} = $self;
  $self->{snmp}->{parent} = $self;
  $self->{rrd}->{parent} = $self;
  return $self;
}

sub error {
  # I had been using Exception::Class::TryCatch and would throw()
  # here, but this presented problems in perl 5.8.8 where catch()
  # would use @DB::args in a way that would trigger the error
  # "Bizarre copy of HASH in aassign at /usr/local/lib/perl5/site_perl/5.8.0/Devel/StackTrace.pm line 67"
  # Which is also seen here:
  # http://www.perlmonks.org/index.pl?node_id=293338
  #
  # So, instead we revert to the old perl standby of eval {}; if ($@) {};
  my $self = shift;
  die "@_";
}

sub logger {
  # Simple logging where logfile is set during startup
  # to either a file handle or STDOUT.
  my $self = shift;
  my $fh = $self->{logfh};
  die "no logfile defined, run prepare_logger"
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
  exit;
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

# FIXME: Avoiding the use of a configuration file for now.
#sub read_config {
#  # Read a simple configuration file that contains a hash object
#  # and subroutines.
#  my $self = shift;
#
#  # abs_path for config file path
#  #use File::Basename;
#  use Cwd qw/abs_path/;
#  # YAML has Load
#  use YAML::XS qw/Load/;
#  # Slurp has read_file
#  use File::Slurp qw/read_file/;
#
#  $self->local_debug("read_config()\n");
#
#  return
#    if (! defined $self->{configfile});
#
#  $self->error("no such file: $self->{configfile}\n")
#    if (! -f $self->{configfile});
#
#  my $configfile = abs_path($self->{configfile});
#
#  $self->{config} = Load scalar read_file($configfile) ||
#    $self->error("error loading config file '$configfile': $!\n");
#
#  # Validate configuration, required fields.
#  my @required = ( 'db_tries','cachefile' );
#  foreach my $req (@required) {
#    $self->error("configuration is missing required parameter '$req'\n")
#      if (! exists $self->{config}->{$req});
#  }
#  foreach my $key (keys %{ $self->{config} } ) {
#    $self->{$key} = $self->{config}->{$key}
#      if (exists $self->{$key});
#  }
#}

sub parse_disk_conf {
  # Read the config file and find NFS servers.
  # This currently supports reading disk.conf as well as the gscmnt autoconfig file.

  my $self = shift;

  $self->local_debug("parse_disk_conf()\n");
  $self->error("disk configuration file is undefined, use -D\n")
    if (! defined $self->{diskconf} or ! -f $self->{diskconf});
  $self->local_debug("using disk config file: $self->{diskconf}\n");

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
  # Target host may be a CLI arg or come from a config file.

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
    if (defined $self->{hosts}) {
      my @list = split(/,/,$self->{hosts});
      foreach my $host (@list) {
        $hosts->{$host} = {};
      }
    }
  }


  return $hosts;
}

sub cache {
  # Iterate over the result hash and add to sqlite cache.
  my $self = shift;
  my $host = shift;
  my $result = shift;
  my $err = shift;

  return if (! defined $host);
  return if (! defined $result);

  $self->local_debug("cache($host,$result,$err)\n");

  foreach my $key (keys %$result) {
    $self->{cache}->disk_df_add($result->{$key});
  }

  $self->{cache}->disk_hosts_add($host,$result,$err);

  $self->{cache}->validate_volumes();
}

sub host_is_current {
  # Look in the cache at last_modified and check if the
  # delta between now and then is less than max age.
  my $self = shift;
  my $host = shift;

  $self->local_debug("host_is_current()\n");

  return 0 if ($self->{force});

  my $result = $self->{cache}->sql_exec('SELECT last_modified FROM disk_hosts WHERE hostname = ?',($host));
  return 0 if (scalar @$result < 1);

  my $date0 = $result->[0]->[0];
  return 0 if ($date0 eq "0000-00-00 00:00:00");

  $date0 = ParseDate($result->[0]->[0]);
  return 0 if (! defined $date0);

  my $err;
  my $date1 = ParseDate(scalar gmtime());
  my $calc = DateCalc($date0,$date1,\$err);

  $self->error("Error in DateCalc: $date0, $date1, $err\n")
    if ($err);
  $self->error("Error in DateCalc: $date0, $date1, $err\n")
    if (! defined $calc);

  my $delta = Delta_Format($calc,0,'%st');
  return 0 if (! defined $delta);

  $self->local_debug("hrs delta: $calc => $delta sec\n");
  return 1
    if $delta < $self->{host_maxage};

  return 0;
}

sub parse_args {

  my $self = shift;
  my %opts;

  getopts("dfFhVD:H:i:l:pr:t:v:",\%opts) or
    $self->error("Error parsing options\n");

  if ($opts{'h'}) {
    pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
    exit;
  }
  if ($opts{'V'}) {
    $self->version();
  }

  #$self->{configfile} = delete $opts{'C'};
  $self->{force} = delete $opts{'f'} ? 1 : 0;
  $self->{recache} = delete $opts{'F'} ? 1 : 0;
  $self->{debug} = delete $opts{'d'} ? 1 : 0;
  $self->{purge} = delete $opts{'p'} ? 1 : 0;
  $self->{diskconf} = delete $opts{'D'};
  $self->{hosts} = delete $opts{'H'};
  $self->{logfile} = delete $opts{'l'};
  $self->{timeout} = delete $opts{'t'}
    if ($opts{'t'});
  $self->{cachefile} = delete $opts{'i'}
    if ($opts{'i'});
  $self->{rrdpath} = delete $opts{'r'}
    if ($opts{'r'});
  $self->{vol_maxage} = delete $opts{'v'}
    if ($opts{'v'});
}

sub update_cache {
  # Build the sqlite cache for every host found.

  my $self = shift;
  my $hosts = shift;

  $self->local_debug("update_cache()\n");

  $self->{cache}->prep();

  # Purge aging cache data
  if ($self->{purge}) {
    $self->{cache}->purge_volumes();
    return 0;
  }

  foreach my $host (keys %$hosts) {
    # Have to queried this host recently?
    if (! $self->host_is_current($host) ) {
      print "Querying host $host\n";
      # Query the host and cache the result
      my $result = {};
      my $error = 0;
      eval {
        $result = $self->{snmp}->query_snmp($host);
      };
      if ($@) {
        # log here, but not fatally
        $self->logger("snmp error: $host: $@\n");
        $error = 1;
      }
      $self->cache($host,$result,$error);
    } else {
      print "host $host is current\n";
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
  # FIXME: remove use of yaml?
  #$self->read_config();

  # Define list of hosts to query
  my $hosts = $self->define_hosts(@ARGV);

  # Build/update the cache of data
  $self->update_cache($hosts);

  $self->logger("queried " . ( scalar keys %$hosts ) . " host(s)\n");

  # Now that the cache is built/updated, create/update RRD files.
  $self->{rrd}->run();

  print "Complete\n";

  return 0;
}

1;

__END__

=pod

=head1 NAME

DiskUsage - Gather disk consumption data

=head1 SYNOPSIS

  disk_usage [options]

=head1 OPTIONS

 -d         Enable debug mode.
 -f         Refresh data even if current.
 -F         Refresh disk group name even if cached (mounts over NFS).
 -h         This useful documentation.
 -V         Display version.
 -p         Purge cache data that is older than -v [days].
 -v [days]  Set max age in days of volume data (default 15 days).
 -t [num]   Set SNMP timeout (default 15 seconds).
 -H [LIST]  Set comma separated list of hosts to add to disk config file.
 -D [file]  Specify disk config file.
 -i [file]  Set file path for cache file.
 -l [file]  Set file path for log file.
 -r [path]  Set path to RRD files.

=head1 DESCRIPTION

This module gathers disk usage information.

=cut
