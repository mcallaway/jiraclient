#!/usr/bin/perl

package gpfsmapper::Error;

use Exception::Class (
  "gpfsmapper::Error",
  "gpfsmapper::Errors" =>
    { isa => "gpfsmapper::Error" },
  "gpfsmapper::Errors::Recoverable" =>
    { isa => "gpfsmapper::Error" },
  "gpfsmapper::Errors::Fatal" =>
    { isa => "gpfsmapper::Error" },
);

package gpfsmapper;

# option parsing
use Getopt::Std;
# for pod2usage function
use Pod::Find qw(pod_where);
use Pod::Usage;
# for debugging
use Data::Dumper;

our $VERSION = "0.1.0";

sub new {
  my $class = shift;
  $self = {
    config => undef,
    mpconfig => '/etc/multipath.conf',
    dm_map => {},
    wwid_map => {},
    array_map => {},
  };
  bless $self, $class;
  return $self;
}

sub warn {
  my $self = shift;
  printf STDERR "@_";
}

sub error {
  my $self = shift;
  gpfsmapper::Error->throw( error => "@_" );
}

sub version {
  my $self = shift;
  print "gpfsmapper $VERSION\n";
  exit 0;
}

sub read_config {
  # Read the config file specified to get the friendly name map.
  # File has format:
  #   key value
  #   ...
  my $self = shift;
  $self->{array_map} = undef;

  $self->error("configuration file not defined\n")
    if (! defined $self->{config});
  $self->error("configuration file not found: $self->{config}\n")
    if (! -f $self->{config});
  $self->error("configuration file is empty: $self->{config}\n")
    if (! -s $self->{config});

  open(FH,"<$self->{config}") or
    $self->error("open failed: $self->{config}: $!\n");

  my $error = 0;
  while (<FH>) {
    chomp;
    next if (/^($|#)/);
    my ($key,$value) = split();
    if ($key !~ /^[a-f0-9]{29}/) {
      $self->warn("invalid WWID: chars not in [a-f0-9]: $key\n");
      $error = 1;
    }
    if (length($key) != 29) {
      $self->warn("invalid WWID: not 29 chars long: $key\n");
      $error = 1;
    }
    if (! defined $value) {
      $self->warn("invalid alias: undefined: $value\n");
      $error = 1;
    }
    $self->{array_map}->{$key} = $value;
  }
  close(FH);
  $self->error("failed to parse config: $self->{config}\n")
    if ($error);

  # Array map should be non-empty
  $self->error("configuration file is empty: $self->{config}\n")
    if (! defined $self->{array_map} );
}

sub run_multipath {

  my $self = shift;

  my $mp = `which multipath 2>/dev/null`;
  my $rc = $? >> 8;
  chomp $mp;
  $self->error("cannot find 'multipath' in PATH\n")
    if ($rc or length($mp) == 0);

  open(MP,"$mp -l |") or
    $self->error("cannot exec multipath: $mp: $!");
  while (<MP>) {
    if (/(^[0-9a-z]{33})\s+(dm-\d+)/
        or /^\S+\s\(([0-9a-f]{33})\)\s+(dm-\d+)/) {
      $wwid = $1;
      $dmid = $2;
      $arrayid = substr($wwid,0,29);
      $lunid = substr($wwid,-4);
      if (! exists($self->{array_map}->{$arrayid})) {
        $self->error("No friendly name known for array: $arrayid\n");
      }
      $self->{dm_map}->{$dmid} = $self->{array_map}->{$arrayid} . $lunid;
      $self->{wwid_map}->{$wwid} = $self->{array_map}->{$arrayid} . $lunid;
    }
  }
  close(MP);

}

sub read_multipath_conf {

  my $self = shift;
  my $print = shift;

  my $mpconfig = $self->{mpconfig};
  $self->error("cannot find 'multipath.conf' at $mpconfig\n")
    if (! -f $mpconfig);

  # read in existing multipath.conf
  my @mpfile;
  open(CONF,"<$mpconfig") or
    $self->error("open failed: $mpconfig: $!\n");
  while (<CONF>) {
    last if (/^multipaths/);
    push @mpfile, $_;
  }
  close(CONF);
  return join('',@mpfile);
}

sub print_multipath {
  my $self = shift;

  print $self->read_multipath_conf();
  print "multipaths {\n";
  foreach my $wwid (sort keys %{ $self->{wwid_map} }) {
    print  "  multipath {\n";
    print  "    wwid $wwid\n";
    print  "    alias $self->{wwid_map}->{$wwid}\n";
    print  "  }\n";
  }
  print "}\n";
}

sub read_mmlscluster {
  my $self = shift;

  my $mm = `which mmlscluster 2>/dev/null`;
  my $rc = $? >> 8;
  chomp $mm;
  $self->error("cannot find 'mmlscluster' in PATH\n")
    if ($rc or length($mm) == 0);
  open(MM,"$mm |") or
    $self->error("cannot exec mmlscluster: $mm: $!");
  my @hosts;
  my $seen = 0;
  while (<MM>) {
    $seen = 1 if (/Node/);
    next unless ($seen);
    if (/^\s+\d+\s+(\S+)\s+/) {
      push @hosts,$1;
    }
  }
  close(MM);

  foreach my $dmid (sort keys %{ $self->{dm_map} }) {
    print "$dmid:" . join(',',@hosts) . "::dataAndMetadata::$self->{dm_map}->{$dmid}\n";
    push @hosts, (shift @hosts);
  }
}

sub run() {
  my $self = shift;
  my %opts;

  getopts("c:dhmv",\%opts) or
    $self->error("error parsing args\n");

  if (delete $opts{h}) {
    pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
    exit 0;
  }

  $self->version() if (delete $opts{v});
  $self->{config} = delete $opts{c};
  $self->read_config();

  if (scalar keys %opts < 1) {
    pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
    exit 1;
  }

  $self->run_multipath();

  # Parse multipath output for use by mmlscluster
  $self->print_multipath() if (delete $opts{m});
  $self->read_mmlscluster() if (delete $opts{d});
}

package main;

use strict;
use warnings;

my $caller = ${ [ caller() ] }[0];
if (! defined($caller) or $caller eq "PAR") {
  my $app = gpfsmapper->new();
  $app->run();
}

1;

__END__

=pod

=head1 NAME

gpfsmapper - Produce a mapping of SCSI LUN to friendly name.

=head1 SYNOPSIS

gpfsmapper [options]

=head1 OPTIONS

 -c [file]  Specify config file
 -d         Output the disk list from mlscluster
 -h         This helpful message
 -m         Output an updated 'multipath.conf' file
 -v         Print version information

=head1 DESCRIPTION

This script reads 'multipath -l' output, 'mmlscluster' output, and
uses a configuration file to produce the multipaths section of the
multipath.conf file, applying the friendly name.  It also can output
a disk list for use with a GPFS cluster.

=cut

