
package DiskUsage::SNMP;

use strict;
use warnings;

use File::Basename;
use POSIX;
use Net::SNMP;
use Data::Dumper;

# Autoflush
local $| = 1;

# Add commas to big numbers
my $comma_rx = qr/\d{1,3}(?=(\d{3})+(?!\d))/;
# Convention for all NFS exports
my @prefixes = ("/vol","/home");

# A mapping of disk related OIDs
my $oids = {
  # use sysDescr to spot Linux vs. NetApp vs. GPFS, other
  'sysDescr'       => '1.3.6.1.2.1.1.1.0',
  'sysName'        => '1.3.6.1.2.1.1.5.0',
  'linux'          => {
    # linux OIDs for volumes and consumption
    'hrStorageEntry' => '1.3.6.1.2.1.25.2.3.1.0',
    #'hrStorageIndex' => '1.3.6.1.2.1.25.2.3.1.1',
    #'hrStorageType'  => '1.3.6.1.2.1.25.2.3.1.2',
    'hrStorageDescr' => '1.3.6.1.2.1.25.2.3.1.3',
    'hrStorageAllocationUnits' => '1.3.6.1.2.1.25.2.3.1.4',
    'hrStorageSize'  => '1.3.6.1.2.1.25.2.3.1.5',
    'hrStorageUsed'  => '1.3.6.1.2.1.25.2.3.1.6',
    'extTable'       => '1.3.6.1.4.1.2021.8',
    'nsExtendOutLine' => '1.3.6.1.4.1.8072.1.3.2.4.1.2',
  },
  'netapp'           => {
    'dfFileSys'      => '1.3.6.1.4.1.789.1.5.4.1.2',
    'dfHighTotalKbytes'  => '1.3.6.1.4.1.789.1.5.4.1.14',
    'dfLowTotalKbytes'   => '1.3.6.1.4.1.789.1.5.4.1.15',
    'dfHighUsedKbytes'   => '1.3.6.1.4.1.789.1.5.4.1.16',
    'dfLowUsedKbytes'    => '1.3.6.1.4.1.789.1.5.4.1.17',
  },
  'gpfs'             => {
    'processList'    => '1.3.6.1.2.1.25.4.2.1.2',
    'hrStorageDescr' => '1.3.6.1.2.1.25.2.3.1.3',
    'hrStorageAllocationUnits' => '1.3.6.1.2.1.25.2.3.1.4',
    'hrStorageSize'  => '1.3.6.1.2.1.25.2.3.1.5',
    'hrStorageUsed'  => '1.3.6.1.2.1.25.2.3.1.6',
  },
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
  die "@_";
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

sub snmp_get_request {
  my $self = shift;
  my $args = shift;
  my $result = {};
  eval {
    $result = $self->{snmp_session}->get_request(-varbindlist => $args );
  };
  if ($@ or length($self->{snmp_session}->error())) {
    $self->error("SNMP error in request: $@: " . $self->{snmp_session}->error() . "\n");
  }
  return $result;
}

sub snmp_get_table {
  my $self = shift;
  my $baseoid = shift;
  my $result = {};
  $self->local_debug("snmp_get_table($baseoid)\n");
  eval {
    $result = $self->{snmp_session}->get_table(-baseoid => $baseoid);
  };
  if ($@ or length($self->{snmp_session}->error())) {
    $self->error("SNMP error in request: $@: " . $self->{snmp_session}->error() . "\n");
  }
  return $result;
}

sub spot_gpfs {
  # HOST-RESOURCES-MIB::hrSWRunName = gpfsSwapdKproc
  my $self = shift;
  $self->local_debug("spot_gpfs()\n");
  my $res = $self->snmp_get_table( $oids->{'gpfs'}->{'processList'} );
  my @processes = values %$res;
  return 1 if grep /gpfsSwapdKproc/, @processes;
  return 0;
}

sub type_string_to_type {
  my $self = shift;
  my $typestr = shift;

  $self->local_debug("type_string_to_type($typestr)\n");

  # List of regexes that map sysDescr to a system type
  my %dispatcher = (
    qw/^Linux/ => 'linux',
    qw/^NetApp/ => 'netapp',
  );

  foreach my $regex (keys %dispatcher) {
    if ($typestr =~ $regex) {
      my $type = $dispatcher{$regex};
      # Spot gpfs among linux hosts
      if ($type eq 'linux') {
        $type = 'gpfs' if ($self->spot_gpfs());
      }
      $self->local_debug("host is type: $type\n");
      return $type;
    }
  }

  $self->error("No such host type defined for: $typestr");
}

sub get_host_type {
  my $self = shift;
  my $sess = $self->{snmp_session};
  $self->local_debug("get_host_type()\n");
  my $res = $self->snmp_get_request( [ $oids->{'sysDescr'} ] );
  my $typestr = pop @{ [ values %$res ] };
  return $self->type_string_to_type($typestr);
}

sub netapp_int32 {
  my $self = shift;
  my $low = shift;
  my $high = shift;
  if ($low >= 0) {
    return $high * 2**32 + $low;
  }
  if ($low < 0) {
    return ($high + 1) * 2**32 + $low;
  }
}

sub get_snmp_disk_usage {
  my $self = shift;
  my $result = shift;

  $self->local_debug("get_snmp_disk_usage()\n");

  # What is the target
  my $host_type = $self->get_host_type();

  # Fetch all volumes on target linux host
  my $ref;
  if ($host_type eq 'netapp') {
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'dfFileSys'} );
  } else {
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'hrStorageDescr'} );
  }

  # Iterate over all volume points
  foreach my $volume_path_oid (keys %$ref) {
    # Iterate over subset of volumes that we export, based on
    # a naming convention adopted by Systems team.
    foreach my $prefix (@prefixes) {

      if (defined $ref->{$volume_path_oid} and $ref->{$volume_path_oid} =~ /^$prefix/) {

        my $id = pop @{ [ split /\./, $volume_path_oid ] };

        # FIXME This is a mess...

        # Create arg list for SNMP
        my @args;
        my @items;
        if ($host_type eq 'netapp') {
          @items = ('dfHighTotalKbytes','dfLowTotalKbytes','dfHighUsedKbytes','dfLowUsedKbytes');
        } else {
          @items = ('hrStorageUsed','hrStorageSize','hrStorageAllocationUnits');
        }
        foreach my $item (@items) {
          my $oid = $oids->{$host_type}->{$item} . ".$id";
          push @args, $oid;
        }

        # Query SNMP
        my $disk = $self->snmp_get_request( \@args );

        my $total;
        my $used;

        # Convert result blocks to bytes
        if ($host_type eq 'netapp') {
          # Fix 32 bit integer stuff
          my $low = $disk->{$oids->{$host_type}->{'dfLowTotalKbytes'} . ".$id"};
          my $high = $disk->{$oids->{$host_type}->{'dfHighTotalKbytes'} . ".$id"};
          $total = $self->netapp_int32($low,$high);

          $low = $disk->{$oids->{$host_type}->{'dfLowUsedKbytes'} . ".$id"};
          $high = $disk->{$oids->{$host_type}->{'dfHighUsedKbytes'} . ".$id"};
          $used = $self->netapp_int32($low,$high);

        } else {
          # Correct for block size
          my $correction = $disk->{$oids->{$host_type}->{'hrStorageAllocationUnits'} . ".$id"} / 1024;
          $total = $disk->{$oids->{$host_type}->{'hrStorageSize'} . ".$id"} * $correction;
          $used = $disk->{$oids->{$host_type}->{'hrStorageUsed'} . ".$id"} * $correction;
        }

        # Empty hash if not present
        $result->{$ref->{$volume_path_oid}} = {} if (! defined $result->{$ref->{$volume_path_oid}} );

        # Add mount point
        $result->{$ref->{$volume_path_oid}}->{'mount_path'} = $self->get_mount_point($ref->{$volume_path_oid});

        # The last digit in the OID is the volume we want

        # Account for reported block size in size calculation, track in KB
        # Correct for signed 32 bit INTs
        $result->{$ref->{$volume_path_oid}}->{'used_kb'} = $used;
        $result->{$ref->{$volume_path_oid}}->{'total_kb'} = $total;

        $result->{$ref->{$volume_path_oid}}->{'physical_path'} = $ref->{$volume_path_oid};
      }
    }
  }
}

sub get_mount_point {
  # Map a volume to a mount point.

  my $self = shift;
  my $volume = shift;

  # This is noisy
  #$self->local_debug("get_mount_point\n");

  # These mount points are agreed upon by convention.
  # Return empty if the $volume is shorter than the
  # hash keys, preventing a substr() error on too short mounts.
  return '' if (length($volume) <= 4);
  my $mapping = {
    qr|^/vol| => "/gscmnt" . substr($volume,4),
    qr|^/home(\d+)| => "/gscmnt" . substr($volume,5),
  };

  foreach my $rx (keys %$mapping) {
    return $mapping->{$rx}
      if ($volume =~ /$rx/);
  }
}

sub get_disk_group {
  # Look on a mount point for a DISK_ touch file.

  my $self = shift;
  my $physical_path = shift;
  my $mount_path = shift;
  my $group_name;

  $self->local_debug("get_disk_group($physical_path,$mount_path)\n");

  # Does the cache already have the disk group name?
  my $res = $self->{parent}->{cache}->fetch_disk_group($mount_path);
  if (defined $res and scalar @$res > 0 and ! $self->{parent}->{recache}) {
    $self->local_debug("res: " . Dumper($res));
    $group_name = pop @{ pop @$res };
    $self->local_debug("$mount_path is cached for: $group_name\n");
    return $group_name;
  }

  # Determine the disk group name.
  my $host_type = $self->get_host_type();
  if ($host_type eq 'linux') {
    # Try SNMP for linux hosts, which may have been configured to
    # report disk group touch files via SNMP.
    my $ref = $self->snmp_get_table( $oids->{$host_type}->{'nsExtendOutLine'} );
    foreach my $touchfile (values %$ref) {
      $touchfile =~ /^(.*)\/(\S+)/;
      my $dirname = $1;
      my $group_name = $2;
      return $group_name if ($dirname eq $physical_path);
    }
  }

  # This will actually mount a mount point via automounter.
  # Be careful to not overwhelm NFS servers.
  # NB. This is a convention from Storage team to use DISK_ touchfiles.
  my $file = pop @{ [ glob("$mount_path/DISK_*") ] };
  if (defined $file and $file =~ m/^\S+\/DISK_(\S+)/) {
    $group_name = $1;
  } else {
    $group_name = 'unknown';
  }
  $self->local_debug("$mount_path is group: $group_name\n");
  return $group_name;
}

# Query a SNMP host and ask for disk usage info
sub connect_snmp {
  my $self = shift;
  my $host = shift;

  $self->local_debug("connect_snmp($host)\n");

  my ($sess,$err);
  eval {
    ($sess,$err) = Net::SNMP->session(
     -hostname => $host,
     -community => 'gscpublic',
     -version => '2c',
     -timeout => 5,
     -retries => 1,
     -debug => 0x20,
    );
  };
  if ($@ or ! defined $sess) {
    $self->error("SNMP failed to connect to host: $host: $err\n");
  }

  if (defined $self->{snmp_session}) {
    $self->{snmp_session}->close();
  }

  # Note: We're returning some big messages!
  $sess->max_msg_size(15000);

  $self->{snmp_session} = $sess;
}

sub query_snmp {
  my $self = shift;
  my $host = shift;
  my $result = {};

  $self->connect_snmp($host);

  # Query SNMP for df stats
  $self->get_snmp_disk_usage($result);

  foreach my $physical_path (keys %$result) {
    $result->{$physical_path}->{'group_name'} = $self->get_disk_group($physical_path,$result->{$physical_path}->{'mount_path'});
  }

  return $result;
}

1;
