
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
my @prefixes = ("/vol","/home","/gpfs");

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
    'nsExtendOutput2Table'  => '1.3.6.1.4.1.8072.1.3.2.4',
    'nsExtendOutLine'       => '1.3.6.1.4.1.8072.1.3.2.4.1.2',
    'nsExtendOutLine-gpfs'  => '1.3.6.1.4.1.8072.1.3.2.4.1.2.4.103.112.102.115.1',
    'nsExtendOutLine-group' => '1.3.6.1.4.1.8072.1.3.2.4.1.2.15.100.105.115.107.95.103.114.111.117.112.95.110.97.109.101',
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
    no_snmp => 0,
    is_gpfs => undef,
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

  $self->local_debug("snmp_get_request( " . Dumper($args) . ")\n");
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

sub spot_gpfsswapd {
  my $self = shift;
  my $res;
  $self->local_debug("spot_gpfsswapd\n");

  # This takes a long time because the process list is big.
  eval {
    $res = $self->snmp_get_table( $oids->{'gpfs'}->{'processList'} );
  };
  if ($@ or length($self->{snmp_session}->error())) {
    my $msg = $self->{snmp_session}->error();
    if ($msg =~ /No response/) {
      $self->logger("took too long looking for gpfs processes...proceeding\n");
    } elsif ($msg =~ /Message size exceeded/) {
      my $size = $self->{snmp_session}->max_msg_size();
      return 0 if ($size == 12000); # don't repeat more than once
      $self->{snmp_session}->max_msg_size(12000); # try larger msg size once
      return $self->spot_gpfsswapd();
    } else {
      $self->error($self->{snmp_session}->error());
    }
  }
  my @processes = values %$res;
  return 1 if grep /gpfsSwapdKproc/, @processes;
  return 0;
}

sub spot_gpfsext {
  my $self = shift;
  my $res;

  $self->local_debug("spot_gpfsext()\n");

  eval {
    my $oid = $oids->{'linux'}->{'nsExtendOutLine-gpfs'};
    $res = $self->snmp_get_request( [ $oid ] );
  };
  if ($@ or length($self->{snmp_session}->error())) {
    my $msg = $self->{snmp_session}->error();
    print Dumper("msg: " . $msg);
    if ($msg =~ /No response/) {
      $self->logger("took too long looking for gpfs processes...proceeding\n");
    } elsif ($msg =~ /Message size exceeded/) {
      my $size = $self->{snmp_session}->max_msg_size();
      return 0 if ($size == 12000); # don't repeat more than once
      $self->{snmp_session}->max_msg_size(12000);
      return $self->spot_gpfsext();
    } else {
      $self->error($self->{snmp_session}->error());
    }
  }
  my $result = pop @{ [ values %$res ] };
  return 1 if ($result eq 'true');
  return 0;
}

sub spot_gpfs {
  # HOST-RESOURCES-MIB::hrSWRunName = gpfsSwapdKproc
  my $self = shift;

  return $self->{is_gpfs} if (defined $self->{is_gpfs});
  $self->local_debug("spot_gpfs()\n");
  my $result = 0;

  #my $result = $self->spot_gpfsswapd();
  $result = $self->spot_gpfsext();

  $self->local_debug("is_gpfs: $result\n");
  $self->{is_gpfs} = $result;
  return $result;
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
      # FIXME: perhaps just use naming convention in mount_path
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

  # Need to know what sort of host this is to see what SNMP tables to ask for.
  my $host_type = $self->get_host_type();

  # Fetch all volumes on target host
  my $ref;
  if ($host_type eq 'netapp') {
    # NetApp is different than Linux
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'dfFileSys'} );
  } else {
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'hrStorageDescr'} );
  }

  # Iterate over all volumes and get consumption info.
  foreach my $volume_path_oid (keys %$ref) {
    # Iterate over subset of volumes that we export, based on
    # a naming convention adopted by Systems team.
    foreach my $prefix (@prefixes) {

      if (defined $ref->{$volume_path_oid} and $ref->{$volume_path_oid} =~ /^$prefix/) {

        my $id = pop @{ [ split /\./, $volume_path_oid ] };

        # FIXME This is a mess...

        # Create arg list for SNMP, what to ask for.
        my @args;
        my @items;
        if ($host_type eq 'netapp') {
          # NetApps do this
          @items = ('dfHighTotalKbytes','dfLowTotalKbytes','dfHighUsedKbytes','dfLowUsedKbytes');
        } else {
          # Linux boxes do this
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

sub get_disk_group_via_snmp {
  my $self = shift;
  my $physical_path = shift;
  my $mount_path = shift;

  $self->local_debug("get_disk_group_via_snmp\n");

  # Try SNMP for linux hosts, which may have been configured to
  # report disk group touch files via SNMP.  Save the result so
  # we only query SNMP once per host per run.
  if (! defined $self->{groups}) {
    eval {
      my $oid = $oids->{'linux'}->{'nsExtendOutLine-group'};
      $self->{groups} = $self->snmp_get_table( $oid );
    };
    if ($@ or length($self->{snmp_session}->error())) {
      my $msg = $self->{snmp_session}->error();
      if ($msg =~ /No response/) {
        $self->logger("took too long looking for groups via snmp...proceeding\n");
      } elsif ($msg =~ /The requested table is empty/) {
        $self->logger("this host doesn't serve groups via snmp...proceeding\n");
        $self->{no_snmp} = 1;
      } elsif ($msg =~ /Message size exceeded/) {
        my $size = $self->{snmp_session}->max_msg_size();
        return if ($size == 12000); # don't do this twice
        $self->logger("query snmp again with larger message size...\n");
        $self->{snmp_session}->max_msg_size(12000); # try larger size
        return $self->get_disk_group_via_snmp($physical_path,$mount_path);
      } else {
        $self->error($self->{snmp_session}->error());
      }
    }
  }
  foreach my $touchfile (values %{ $self->{groups} } ) {
    $touchfile =~ /^(.*)\/DISK_(\S+)/;
    my $dirname = $1;
    my $group_name = $2;
    if ($dirname eq $physical_path) {
      $self->local_debug("snmp says $mount_path belongs to $group_name\n");
      return $group_name;
    }
  }
  return 'unknown';
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
    $group_name = pop @{ pop @$res };
    $self->local_debug("$mount_path is cached for: $group_name\n");
    return $group_name;
  }

  $self->local_debug("no group known for $mount_path\n");

  # Determine the disk group name.
  my $host_type = $self->get_host_type();
  if ($host_type eq 'linux' and ! $self->{no_snmp}) {
    my $group_name = $self->get_disk_group_via_snmp($physical_path,$mount_path);
    return $group_name if (defined $group_name);
  }

  $self->local_debug("mount $mount_path and look for touchfile\n");

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
  my $timeout = int($self->{parent}->{timeout});

  $self->local_debug("connect_snmp($host)\n");

  my ($sess,$err);
  eval {
    ($sess,$err) = Net::SNMP->session(
     -hostname => $host,
     -community => 'gscpublic',
     -version => '2c',
     -timeout => $timeout,
     -retries => 1,
     -debug => 0x20,
    );
  };

  # SNMP connection debugging
  #$sess->debug( [ 0x2, 0x4, 0x8, 0x10, 0x20 ] )
  #  if ($self->{parent}->{debug});

  if ($@ or ! defined $sess) {
    $self->error("SNMP failed to connect to host: $host: $err\n");
  }

  if (defined $self->{snmp_session}) {
    $self->{snmp_session}->close();
  }

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
