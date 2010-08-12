
package DiskUsage::SNMP;

use strict;
use warnings;

use File::Basename;
use POSIX;
use Net::SNMP;
use Data::Dumper;

use DiskUsage::TryCatch;
use DiskUsage::Error;

# Autoflush
local $| = 1;

# Add commas to big numbers
my $comma_rx = qr/\d{1,3}(?=(\d{3})+(?!\d))/;
# Convention for all NFS exports
my @prefixes = ("/vol","/home");

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
  my $class = shift;
  my $self = {
    parent => shift,
  };  bless $self, $class;
  return $self;
}

sub error {
  # Raise an Exception object.
  my $self = shift;
  $self->logger("Error: @_");
  DiskUsage::Error->throw( error => @_ );
}

sub logger {
  my $self = shift;
  my $fh = $self->{parent}->{logfh};
  $fh = \*STDERR if (! defined $fh);
  print $fh localtime() . ": @_";
}

sub local_debug {
  my $self = shift;
  $self->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}


sub get_snmp_disk_usage {
  # Query host via SNMP for disk usage.

  my $self = shift;
  my $sess = shift;
  my $result = shift;

  $self->local_debug("get_snmp_disk_usage()\n");

  # Fetch all mounts on target host
  my $ref = $sess->get_table($oids->{'hrStorageDescr'});
  if (! defined $ref) {
    $self->error("SNMP returned no data: " . $sess->error() . "\n");
  }

  # Identify NFS exports...
  my @keys = ();
  foreach my $key (keys %$ref) {

    foreach my $prefix (@prefixes) {

      if (defined $ref->{$key} and $ref->{$key} =~ /^$prefix/) {

        # The last digit in the OID is the mount we want
        my $id = pop @{ [ split /\./, $key ] };

        my $unit = $oids->{'hrStorageAllocationUnits'} . ".$id";
        my $used = $oids->{'hrStorageUsed'} . ".$id";
        my $size = $oids->{'hrStorageSize'} . ".$id";

        my $disk = $sess->get_request(
            -varbindlist => [ $unit, $size, $used ],
            );

        $result->{$ref->{$key}} = {} if (! defined $result->{$ref->{$key}} );

        # Account for reported block size in size calculation, track in KB
        $result->{$ref->{$key}}->{'used_kb'} = $disk->{$used} * ( $disk->{$unit} / 1024 );
        $result->{$ref->{$key}}->{'total_kb'} = $disk->{$size} * ( $disk->{$unit} / 1024 );
        #$result->{$ref->{$key}}->{'mount_path'} = $ref->{$key} =~ s/$prefix/\/gscmnt/;
        $result->{$ref->{$key}}->{'physical_path'} = $ref->{$key};
      }
    }
  }
}

sub get_snmp_disk_groups {
  # Get DISK_ group name via SNMP if possible.

  my $self = shift;
  my $sess = shift;
  my $result = shift;

  $self->local_debug("get_snmp_disk_groups()\n");

  return if (scalar(keys %$result) < 1);

  # FIXME: check if mapping is missing or incomplete
  # Map disk groups if SNMP daemon has been configured to provide it.
  # This is all one long string to be parsed.
  my $ref = $sess->get_request($oids->{'extOutput'});
  if (! defined $ref) {
    $self->error("SNMP returned no data: " . $sess->error() . "\n");
  }

  foreach my $item ( split /\s+/, pop @{ [ values %$ref ] } ) {
      my $volume = dirname $item;
      my $group  = basename $item;
      $group =~ s/^\S+?_//;
      $result->{$volume} = {'group' => $group }
        if ($item ne "noSuchInstance");
  }
}

sub get_mount_point {
  # Map a volume to a mount point.

  my $self = shift;
  my $volume = shift;

  #$self->local_debug("get_mount_point\n");

  # These mount points are agreed upon by convention.
  # Return empty if the $volume is shorter than the
  # hash keys, preventing a substr() error on too short mounts.
  return '' if (length($volume) <= 4);
  my $mapping = {
    qr|^/vol| => "/gscmnt/" . substr($volume,4),
    qr|^/home(\d+)| => "/gscmnt/" . substr($volume,5),
  };

  foreach my $rx (keys %$mapping) {
    return $mapping->{$rx}
      if ($volume =~ /$rx/);
  }
}

sub get_disk_groups {
  # Look on a mount point for a DISK_ touch file.

  my $self = shift;
  my $sess = shift;
  my $result = shift;

  $self->local_debug("get_disk_groups()\n");

  return if (scalar(keys %$result) < 1);

  foreach my $volume (keys %$result) {
    my $mount = $self->get_mount_point($volume);
    $result->{$volume}->{'mount_path'} = $mount;
    # This will actually mount a mount point via automounter.
    # Be careful to not overwhelm NFS servers.
    my $file = pop @{ [ glob("$mount/DISK_*") ] };
    if (! defined $file) {
      $result->{$volume}->{'group_name'} = 'unknown';
    } elsif ($file =~ m/^\S+\/DISK_(\S+)/) {
      $result->{$volume}->{'group_name'} = $1;
    } else {
      $result->{$volume}->{'group_name'} = 'unknown';
    }
  }
}

# Query a SNMP host and ask for disk usage info
sub query_snmp {
  my $self = shift;
  my $host = shift;
  # requires a hostname and a community string as its arguments
  # FIXME: hostname from CLI maybe?
  my $result = {};

  $self->local_debug("query_snmp()\n");

  my ($sess,$err) = Net::SNMP->session(
   -hostname => $host,
   -community => 'gscpublic',
   -version => '2c',
   -timeout => 5,
   -retries => 1,
   -debug => 0x20,
  );

  if (!defined($sess)) {
    printf "Error: %s\n", $err;
    return;
  }

  $self->get_snmp_disk_usage($sess,$result);
  $self->get_snmp_disk_groups($sess,$result);
  $self->get_disk_groups($sess,$result);

  return $result;
}

1;
