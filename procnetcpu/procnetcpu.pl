#!/usr/bin/env perl

package procnetcpu;

use Storable;
use Data::Dumper;

use strict;
use warnings;

our $VERSION = "0.2";

sub new {
  my $class = shift;
  my $self = {
    'cpu' => '/proc/stat',
    'net' => '/proc/net/dev',
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
  $$this = {
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

sub save {
  my $self = shift;
  my $result = shift;
  $self->warn("save run to " . $self->{output} . "\n");
  Storable::store($result,$self->{output});
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
    if (ref($$this->{$key})) {
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
    } else {
      $diff = $$this->{$key} - $last->{$key};
      $$this->{"d_" . $key} = $diff;
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
  $self->read_cpu(\$this);
  $self->read_net(\$this);
  $self->compare($last,\$this);
  $self->save($this);
  $self->display($this);
}

1;

package main;

my $app = procnetcpu->new();
$app->run();
