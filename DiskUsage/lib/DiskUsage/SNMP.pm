
package DiskUsage::SNMP;

use strict;
use warnings;

use File::Basename;
use POSIX;
use Net::SNMP;
use Data::Dumper;
use Log::Log4perl qw/:levels/;

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
    'nsExtendOutLine-group' => '1.3.6.1.4.1.8072.1.3.2.4.1.2.15.100.105.115.107.95.103.114.111.117.112.95.110.97.109.101',
  },
  'netapp'           => {
    'dfFileSys'      => '1.3.6.1.4.1.789.1.5.4.1.2',
    'dfHighTotalKbytes'  => '1.3.6.1.4.1.789.1.5.4.1.14',
    'dfLowTotalKbytes'   => '1.3.6.1.4.1.789.1.5.4.1.15',
    'dfHighUsedKbytes'   => '1.3.6.1.4.1.789.1.5.4.1.16',
    'dfLowUsedKbytes'    => '1.3.6.1.4.1.789.1.5.4.1.17',
  },
};

sub new {
  my $class = shift;
  my $self = {
    parent => shift,
    snmp_session => undef,
    no_snmp => 0,
    hosttype => undef,
    groups => undef,
    logger => Log::Log4perl->get_logger(__PACKAGE__),
  };  bless $self, $class;
  return $self;
}

sub error {
  my $self = shift;
  die "@_";
}

sub snmp_get_request {
  my $self = shift;
  my $args = shift;
  my $result = {};

  $self->{logger}->debug("snmp_get_request( " . Dumper($args) . ")\n");
  eval {
    $result = $self->{snmp_session}->get_request(-varbindlist => $args );
  };
  if ($@ or length($self->{snmp_session}->error())) {
    $self->error("SNMP error in request: $@: " . $self->{snmp_session}->error());
  }
  return $result;
}

sub snmp_get_serial_request {
  # This is a subroutine that hacks around limitations in get_table.
  # get_table will periodically fail because message sizes are bigger
  # or smaller than expected:
  #  /Unexpected end of message/
  #  /Message size exceeded/
  # Using this, we read OIDs incrementally until we get noSuchInstance.
  my $self = shift;
  my $baseoid = shift;
  my $result = {};
  my $res = {};

  $self->{logger}->debug("snmp_get_serial_request( " . Dumper($baseoid) . ")\n");
  my $idx = 1;
  while (1) {
    eval {
      $res = $self->{snmp_session}->get_request(-varbindlist => [ $baseoid . ".$idx" ]);
    };
    if ($@ or length($self->{snmp_session}->error())) {
      $self->error("SNMP error in serial request: " . $self->{snmp_session}->error());
    }
    # Get a single value and if it isn't noSuchInstance, merge it
    # into the result hash.
    my $group = pop @{ [ values %$res ] };
    last if ( $group =~ /noSuch(Instance|Object)/i );
    $result->{ pop @{ [ keys %$res ] } } = pop @{ [ values %$res ] }
      if (defined $res and ref $res eq 'HASH');
    $idx++;
  }
  return $result;
}

sub snmp_get_table {
  my $self = shift;
  my $baseoid = shift;
  my $result = {};
  $self->{logger}->debug("snmp_get_table($baseoid)\n");
  eval {
    $result = $self->{snmp_session}->get_table(-baseoid => $baseoid);
  };
  if ($@ or length($self->{snmp_session}->error())) {
    $self->error("SNMP error in table request: " . $self->{snmp_session}->error());
  }
  return $result;
}

sub type_string_to_type {
  my $self = shift;
  my $typestr = shift;

  $self->{logger}->debug("type_string_to_type($typestr)\n");

  # List of regexes that map sysDescr to a system type
  my %dispatcher = (
    qw/^Linux/ => 'linux',
    qw/^NetApp/ => 'netapp',
  );

  foreach my $regex (keys %dispatcher) {
    if ($typestr =~ $regex) {
      return $dispatcher{$regex};
    }
  }

  $self->error("No such host type defined for: $typestr");
}

sub get_host_type {
  my $self = shift;
  my $sess = $self->{snmp_session};

  $self->{logger}->debug("get_host_type()\n");

  return $self->{hosttype}
    if (defined $self->{hosttype});

  my $res = $self->snmp_get_request( [ $oids->{'sysDescr'} ] );
  my $typestr = pop @{ [ values %$res ] };

  $self->{hosttype} = $self->type_string_to_type($typestr);
  $self->{logger}->debug("host is type: $self->{hosttype}\n");
  return $self->{hosttype};
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

  $self->{logger}->debug("get_snmp_disk_usage()\n");

  # Need to know what sort of host this is to see what SNMP tables to ask for.
  my $host_type = $self->get_host_type();

  # Fetch all volumes on target host
  $self->{logger}->debug("fetch list of volumes...\n");
  my $ref;
  if ($host_type eq 'netapp') {
    # NetApp is different than Linux
    #$ref = $self->snmp_get_serial_request( $oids->{$host_type}->{'dfFileSys'} );
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'dfFileSys'} );
  } else {
    #$ref = $self->snmp_get_serial_request( $oids->{$host_type}->{'hrStorageDescr'} );
    $ref = $self->snmp_get_table( $oids->{$host_type}->{'hrStorageDescr'} );
  }

  # Iterate over all volumes and get consumption info.
  $self->{logger}->debug("get consumption of each volume...\n");
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
        $self->{logger}->debug("get mount point of volume " . $ref->{$volume_path_oid} . "\n");
        $result->{$ref->{$volume_path_oid}}->{'mount_path'} = $self->get_mount_point($ref->{$volume_path_oid});
        $self->{logger}->debug($result->{$ref->{$volume_path_oid}}->{'mount_path'} . "\n");

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
  #$self->{logger}->debug("get_mount_point\n");

  # These mount points are agreed upon by convention.
  # Return empty if the $volume is shorter than the
  # hash keys, preventing a substr() error on too short mounts.
  return '' if (length($volume) <= 4);
  my $mapping = {
    qr|^/vol| => "/gscmnt" . substr($volume,4),
    qr|^/home(\d+)| => "/gscmnt" . substr($volume,5),
    qr|^/gpfs(\S+)| => $volume,
  };

  foreach my $rx (keys %$mapping) {
    return $mapping->{$rx}
      if ($volume =~ /$rx/);
  }
  $self->error("No mount point found for volume: $volume\n");
}

sub get_disk_groups_via_snmp {
  my $self = shift;
  my $physical_path = shift;
  my $mount_path = shift;

  $self->{logger}->debug("get_disk_groups_via_snmp\n");

  # Try SNMP for linux hosts, which may have been configured to
  # report disk group touch files via SNMP.  Save the result so
  # we only query SNMP once per host per run.
  if (! defined $self->{groups}) {
    eval {
      my $oid = $oids->{'linux'}->{'nsExtendOutLine-group'};
      $self->{groups} = $self->snmp_get_serial_request( $oid );
    };
    if ($@ or length($self->{snmp_session}->error())) {
      my $msg = $self->{snmp_session}->error();
      if ($msg =~ /No response/) {
        $self->{logger}->debug("took too long looking for groups via snmp...proceeding\n");
      } elsif ($msg =~ /table is empty/) {
        $self->{logger}->debug("this host doesn't serve groups via snmp...proceeding\n");
        $self->{no_snmp} = 1;
      } elsif ($msg =~ /Message size exceeded/) {
        my $size = $self->{snmp_session}->max_msg_size();
        return if ($size == 12000); # don't do this twice
        $self->{logger}->debug("query snmp again with larger message size...\n");
        $self->{snmp_session}->max_msg_size(12000); # try larger size
        return $self->get_disk_groups_via_snmp($physical_path,$mount_path);
      } elsif ($msg =~ /Unexpected end of/) {
        my $size = $self->{snmp_session}->max_msg_size();
        return if ($size == 12000); # don't do this twice
        $self->{logger}->debug("query snmp again with larger message size...\n");
        $self->{snmp_session}->max_msg_size(12000); # try larger size
        return $self->get_disk_groups_via_snmp($physical_path,$mount_path);
      } else {
        $self->error($self->{snmp_session}->error());
      }
    }
  }
}

sub lookup_disk_group_via_snmp {
  my $self = shift;
  my $physical_path = shift;
  my $mount_path = shift;

  $self->{logger}->debug("lookup_disk_group_via_snmp($physical_path,$mount_path)\n");

  $self->get_disk_groups_via_snmp($physical_path,$mount_path)
    if (! defined $self->{groups});

  foreach my $touchfile (values %{ $self->{groups} } ) {
    $touchfile =~ /^(.*)\/DISK_(\S+)/;
    my $dirname = $1;
    my $group_name = $2;
    if ($dirname eq $physical_path) {
      $self->{logger}->debug("snmp says $mount_path belongs to $group_name\n");
      return $group_name;
    }
  }
  # return undef if group not found in SNMP output
}

sub get_disk_group {
  # Look on a mount point for a DISK_ touch file.

  my $self = shift;
  my $physical_path = shift;
  my $mount_path = shift;
  my $group_name;

  $self->{logger}->debug("get_disk_group($physical_path,$mount_path)\n");

  # Does the cache already have the disk group name?
  my $res = $self->{parent}->{cache}->fetch_disk_group($mount_path);
  if (defined $res and scalar @$res > 0 and ! $self->{parent}->{recache}) {
    $group_name = pop @{ pop @$res };
    $self->{logger}->debug("$mount_path is cached for: $group_name\n");
    return $group_name;
  }

  $self->{logger}->debug("no group known for $mount_path\n");

  # Special case of '.snapshot' mounts
  my $base = basename $physical_path;
  if ($base eq ".snapshot") {
    return 'SYSTEMS_SNAPSHOT';
  }

  # Determine the disk group name.
  my $host_type = $self->get_host_type();
  if ($host_type eq 'linux' and ! $self->{no_snmp}) {
    my $group_name = $self->lookup_disk_group_via_snmp($physical_path,$mount_path);
    # If not defined or empty, go to mount point and look for touch file.
    return $group_name if (defined $group_name and $group_name ne '');
  }

  $self->{logger}->debug("mount $mount_path and look for touchfile\n");

  # This will actually mount a mount point via automounter.
  # Be careful to not overwhelm NFS servers.
  # NB. This is a convention from Storage team to use DISK_ touchfiles.
  my $file = pop @{ [ glob("$mount_path/DISK_*") ] };
  if (defined $file and $file =~ m/^\S+\/DISK_(\S+)/) {
    $group_name = $1;
  } else {
    $group_name = 'unknown';
  }

  $self->{logger}->debug("$mount_path is group: $group_name\n");

  return $group_name;
}

# Query a SNMP host and ask for disk usage info
sub connect_snmp {
  my $self = shift;
  my $host = shift;
  my $timeout = int($self->{parent}->{timeout});

  $self->{logger}->debug("connect_snmp($host)\n");

  my ($sess,$err);
  eval {
    ($sess,$err) = Net::SNMP->session(
     -hostname => $host,
     -community => 'gscpublic',
     -version => '2c',
     -timeout => $timeout,
     -retries => 1,
     -debug => 0x0,
    );
  };

  # SNMP connection debugging
  $sess->debug( [ 0x2, 0x4, 0x8, 0x10, 0x20 ] )
    if ($self->{parent}->{debug});

  if ($@ or ! defined $sess) {
    $self->error("SNMP failed to connect to host: $host: $err");
  }

  if (defined $self->{snmp_session}) {
    $self->{snmp_session}->close();
  }

  $self->{snmp_session} = $sess;
  $self->{hosttype} = undef;
  $self->{groups} = undef;
  $self->{no_snmp} = 0;
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
