#!/usr/bin/perl

package DiskUsage::RRD;

use strict;
use warnings;
use DBI;
use RRDTool::OO;
use Time::Local;

sub new {
  my $class = shift;
  my $self = {
    parent => shift,
  };
  bless $self,$class;
  return $self;
}

sub error {
  # Raise an Exception object.
  my $self = shift;
  $self->{parent}->error(@_);
}

sub logger {
  # Raise an Exception object.
  my $self = shift;
  $self->{parent}->logger(@_);
}

sub local_debug {
  my $self = shift;
  $self->{parent}->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}

sub prep_fake_rrd {
  my $self = shift;
  my $rrd = shift;
  $self->local_debug("prep_fake_rrd\n");

  my $total = 0;
  my $used  = 0;

  my $today =  timelocal(0,0,0,(localtime(time))[3,4,5]);
  my $date =  1234245600;

  $self->create_rrd($rrd,$date);

  until ($date > $today) {
    $date = $date + 86400;
    $total += 1000000000;
    $used += 900000000;
    $rrd->update( time => $date, values => { avail => $total, used => $used } );
  }
}

sub create_rrd {
  my $self = shift;
  $self->local_debug("create_rrd\n");
  my $rrd = shift;
  my $start = shift;

  if (! defined $start) {
    # beginning of today
    $start = timelocal(0,0,0,(localtime(time))[3,4,5]);
  }

  $rrd->create(

      step        => 86400,
      start       => $start,

      data_source => {
        name      => "avail",
        type      => "GAUGE",
      },
      data_source => {
        name      => "used",
        type      => "GAUGE",
      },

      archive     => {
        rows      => 10,
      },
      archive     => {
        rows      => 60,
      },
      archive     => {
        rows      => 180,
      },
      archive     => {
        rows      => 360,
      },
      archive     => {
        rows      => 1800,
      },
  );
}

sub create_or_update {
  my ($self,$group,$total,$used,$cap,$cost) = @_;
  $self->local_debug("create_or_update($group,$total,$used)\n");

  my $rrdpath = $self->{parent}->{rrdpath};
  die "RRD path is unset" if (! defined $rrdpath);
  die "RRD path does not exist" if (! -d $rrdpath);
  my $rrdfile = $rrdpath . "/" . lc($group) . ".rrd";

  my $rrd = RRDTool::OO->new(
    file => $rrdfile,
  );

  if (! -s $rrdfile ) {
    $self->create_rrd($rrd);
  }

  $rrd->update( values => { avail => $total, used => $used } );
}

sub run {
  my $self = shift;

  my $cache = $self->{parent}->{cachefile};
  die "there is no cache to operate on" if (! -f $cache);

  # connect
  my $dbargs = {AutoCommit => 0, PrintError => 1};
  my $dbh = DBI->connect("dbi:SQLite:dbname=$cache","","",$dbargs);

  # select
  my $sql = "SELECT group_name, SUM(total_kb) as tkb, SUM(used_kb) as ukb, ROUND((CAST(SUM(used_kb) AS REAL)/SUM(total_kb) * 100),2) as capacity, (SUM(total_kb)*2500/1000000000) as cost FROM disk_df GROUP BY group_name";
  my $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  my $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  $self->local_debug("Found $sth->rows disk groups");

  # update
  while (my @a = $sth->fetchrow_array() ) {
    $self->create_or_update(@a);
  }
  $sth->finish(); # clean up
}

1;
