#!/usr/bin/env perl

package procnetcpu;

use Storable;
use Data::Dumper;

use strict;
use warnings;

our $VERSION = "0.5";

sub new {
  my $class = shift;
  my $self = {
    'cpu' => '/proc/stat',
    'net' => '/proc/net/dev',
    'fscache' => '/proc/fs/fscache/stats',
    'nfsstat' => '/proc/net/rpc/nfs',
    'output' => 'procnetcpu.cache',
  };
  bless $self, $class;
  return $self;
}

sub error {
  my $self = shift;
  printf STDERR @_;
  exit 1;
}

sub warn {
  my $self = shift;
  printf STDERR @_;
}

sub read_net {
  my $self = shift;
  my $this = shift;

  $self->error("network file error: $self->{net}: $!")
    if (! -f $self->{net});

  # Read network data for each interface and add it to our
  # data structure.
  open (NET,"<$self->{net}");
  while (<NET>) {
    chomp;
    next unless (/:/);
    my $line = $_;
    my $i = {};

    my $idx = index($line,":");
    my $iface = substr($line,0,$idx);
    $iface =~ s/\s+//g; # trim all whitespac
    $line = substr($line,$idx+1);
    $line =~ s/^\s+//; # trim leading whitespace

    my ($rbytes,$rpackets,$rerrs,$rdrop,$rfifo,$rframe,$rcompressed,$rmulticast, $tbytes,$tpackets,$terrs,$tdrop,$tfifo,$tcalls,$tcarrier,$tcompressed) = split(/\s+/,$line);

    $i = {
      'rbytes' => $rbytes,
      'rpackets' => $rpackets,
      'rerrs' => $rerrs,
      'rdrop' => $rdrop,
      'rfifo' => $rfifo,
      'rframe' => $rframe,
      'rcompressed' => $rcompressed,
      'rmulticast' => $rmulticast,
      'tbytes' => $tbytes,
      'tpackets' => $tpackets,
      'terrs' => $terrs,
      'tdrop' => $tdrop,
      'tfifo' => $tfifo,
      'tcalls' => $tcalls,
      'tcarrier' => $tcarrier,
      'tcompressed' => $tcompressed,
    };
    $$this->{'interfaces'}->{$iface} = $i;
  }
  close(NET);
}

sub read_cpu {
  my $self = shift;
  my $this = shift;

  $self->error("cpu file error: $self->{cpu}: $!")
    if (! -f $self->{cpu});

  # Read cpu data and add it to our data structure.
  open (CPU,"<$self->{cpu}");
  my $c = <CPU>;
  close(CPU);
  chomp $c;

  my ($label,$user,$nice,$system,$idle,$iowait,$irq,$softirq) = split(/\s+/,$c);
  $$this->{cpu} = {
    'walltime' => time(),
    'user' => $user,
    'nice' => $nice,
    'system' => $system,
    'idle' => $idle,
    'iowait' => $iowait,
    'irq' => $irq,
    'softirq' => $softirq,
  };
}

sub read_fscache {
  my $self = shift;
  my $this = shift;

  $self->error("fscache file error: $self->{fscache}: $!")
    if (! -f $self->{fscache});

  # Read fscache data and add it to our data structure.
  my $fscache = {};
  open (FS,"<$self->{fscache}");
  while (<FS>) {
    next unless (/:/);
    chomp;
    my ($item,$values) = split(/: /);
    $item =~ s/\s+//g;
    my @values = split(/\s+/,$values);
    my $hash;
    #map { ($a,$b) = split(/=/); $hash->{$a} = int($b); } @values;
    #$fscache->{$item} = $hash;
    map { ($a,$b) = split(/=/); $fscache->{"$item.$a"} = int($b); } @values;
  }
  close(FS);
  $$this->{fscache} = $fscache;
}

sub read_nfsstat {
  my $self = shift;
  my $this = shift;

  $self->error("nfsstat file error: $self->{nfsstat}: $!")
    if (! -f $self->{nfsstat});

  # Read nfsstat data and add it to our data structure.
  my $nfsstat;
  open (FS,"<$self->{nfsstat}");
  while (<FS>) {
    chomp;
    next unless (/^proc3/);
    my @values = split(/\s+/);
    $nfsstat->{getattr} = $values[3];
    $nfsstat->{setattr} = $values[4];
    $nfsstat->{lookup} = $values[5];
    $nfsstat->{access} = $values[6];
    $nfsstat->{readlink} = $values[7];
    $nfsstat->{read} = $values[8];
    $nfsstat->{write} = $values[9];
    $nfsstat->{create} = $values[10];
    $nfsstat->{mkdir} = $values[11];
    $nfsstat->{symlink} = $values[12];
    $nfsstat->{mknod} = $values[13];
    $nfsstat->{remove} = $values[14];
    $nfsstat->{rmdir} = $values[15];
    $nfsstat->{rename} = $values[16];
    $nfsstat->{link} = $values[17];
    $nfsstat->{readdir} = $values[18];
    $nfsstat->{readdirplus} = $values[19];
    $nfsstat->{fsstat} = $values[20];
    $nfsstat->{fsinfo} = $values[21];
    $nfsstat->{pathconf} = $values[22];
    $nfsstat->{commit} = $values[23];
  }
  close(FS);
  $$this->{nfsstat} = $nfsstat;
}

sub save {
  my $self = shift;
  my $result = shift;
  $self->warn("save run to " . $self->{output} . "\n");
  Storable::nstore($result,$self->{output});
}

sub get {
  my $self = shift;
  $self->warn("read last run from " . $self->{output} . "\n");
  return Storable::retrieve($self->{output});
}

sub compare {
  my $self = shift;
  my $last = shift;
  my $this = shift;
  return if (! scalar keys %$last);

  # Compare this run with last run.
  foreach my $key (keys %{$$this}) {
    my $diff;

    if (ref($$this->{$key}) eq "HASH" and
        $key eq 'interfaces' and
        exists $last->{'interfaces'}) {
      # This is a ref, and thus the interfaces reference
      foreach my $iface (keys %{ $$this->{$key} } ) {
        foreach my $item (keys %{ $$this->{$key}->{$iface} } ) {
          my $a = $last->{'interfaces'}->{$iface}->{$item};
          my $b = $$this->{'interfaces'}->{$iface}->{$item};
          $self->error("fatal: field is not numeric: $a")
            if ($a !~ /\d+/);
          $self->error("fatal: field is not numeric: $b")
            if ($b !~ /\d+/);
          #next if ($a !~ /\d+/ or $b !~ /\d+/);
          $diff = $b - $a;
          $$this->{'interfaces'}->{$iface}->{"d_" . $item} = $diff;
        }
      }
    } elsif (ref($$this->{$key}) eq "HASH" and
        $key eq 'fscache' and
        exists $last->{'fscache'}) {
      foreach my $item (keys %{ $$this->{$key} } ) {
          if (! exists $last->{$key}->{$item}) {
            die "no previous record for $item\n";
          }
          my $a = $last->{$key}->{$item};
          my $b = $$this->{$key}->{$item};
          $self->error("fatal: field is not numeric: $a")
            if ($a !~ /\d+/);
          $self->error("fatal: field is not numeric: $b")
            if ($b !~ /\d+/);
          $diff = $b - $a;
          $$this->{$key}->{"d_" . $item} = $diff;
      }
    } elsif (ref($$this->{$key}) eq "HASH" and
        $key eq 'nfsstat' and
        exists $last->{'nfsstat'}) {
      foreach my $item (keys %{ $$this->{$key} } ) {
          if (! exists $last->{$key}->{$item}) {
            die "no previous record for $item\n";
          }
          my $a = $last->{$key}->{$item};
          my $b = $$this->{$key}->{$item};
          $self->error("fatal: field is not numeric: $a")
            if ($a !~ /\d+/);
          $self->error("fatal: field is not numeric: $b")
            if ($b !~ /\d+/);
          $diff = $b - $a;
          $$this->{$key}->{"d_" . $item} = $diff;
      }
    } elsif (ref($$this->{$key}) eq "HASH" and
        $key eq 'cpu' and
        exists $last->{'cpu'}) {
      foreach my $item (keys %{ $$this->{$key} } ) {
        $diff = $$this->{$key}->{$item} - $last->{$key}->{$item};
        $$this->{$key}->{"d_" . $item} = $diff;
      }
    }
  }
}

sub report {
  my $self = shift;
  my $result = shift;

  #print Dumper $result;

  if (exists $result->{cpu}) {
    foreach my $item ('d_idle', 'd_iowait', 'd_irq', 'd_nice', 'd_softirq', 'd_system', 'd_user', 'd_walltime' ) {
      my $name = $item;
      $name =~ s/^d_//;
      print "$name=$result->{cpu}->{$item}\n" if (exists $result->{cpu}->{$item});
    }
  }

  if (exists $result->{interfaces}) {
    my $iface = "eth0";
    foreach my $item ('d_rbytes','d_tbytes') {
      my $name = $item;
      $name =~ s/^d_//;
      print "$name=" . int($result->{interfaces}->{$iface}->{$item}) * 8 . "\n";
    }
    foreach my $item ('d_rpackets','d_tpackets') {
      my $name = $item;
      $name =~ s/^d_//;
      print "$name=" . $result->{interfaces}->{$iface}->{$item} . "\n";
    }
  }

  if (exists $result->{fscache}) {
    while (my ($k,$v) = each %{$result->{fscache}}) {
      next unless ($k =~ /^d_/);
      my $name = $k;
      $name =~ s/^d_//;
      print "$name=$v\n";
    }
  }

  if (exists $result->{nfsstat}) {
    while (my ($k,$v) = each %{$result->{nfsstat}}) {
      next unless ($k =~ /^d_/);
      my $name = $k;
      $name =~ s/^d_//;
      print "$name=$v\n";
    }
  }
}

sub display {
  my $self = shift;
  my $result = shift;

  # Cheap dump:
  $Data::Dumper::Sortkeys = 1;
  print Dumper($result);
  return;

  # Slightly less cheap dump, basically sorts.
  print "cpu\n";
  foreach my $key (sort keys %$result) {
    next if ($key =~ /interfaces/);
    print "$key $result->{$key}\n";
  }
  print "\nnetwork\n";
  foreach my $iface (sort keys %{ $result->{'interfaces'} }) {
    print "$iface\n";
    foreach my $key (sort keys %{ $result->{'interfaces'}->{$iface} }) {
      print "$key $result->{'interfaces'}->{$iface}->{$key}\n";
    }
    print "\n";
  }
}

sub run {
  my $self = shift;
  my $last = {};
  my $this = {};
  if (-f $self->{output}) {
    $last = $self->get();
  }

  $self->read_nfsstat(\$this);
  $self->read_cpu(\$this);
  $self->read_net(\$this);
  $self->read_fscache(\$this);

  my $result = $self->compare($last,\$this);

  $self->save($this);
  if (defined $result) {
    #$self->display($this);
    $self->report($this);
  } else {
    print "no previous run to compare to\n";
  }
}

1;

package main;

my $app = procnetcpu->new();
$app->run();
