#! /usr/bin/env perl

use strict;
use warnings;
use File::Basename qw/basename/;
use above 'Genome';
use Getopt::Std;

sub usage {
  print "Usage: " . basename $0 . " [-vh] <build ids>\n";
  print "   -h    This helpful message\n";
  print "   -v    Be verbose\n";
  exit 1;
}

usage if (! scalar @ARGV);
my %opts;
getopts("vh",\%opts) or usage;
my $verbose = (delete $opts{v}) ? 1 : 0;
usage if ($opts{h});

foreach my $buildid (@ARGV) {
  my $build = Genome::Model::Build->get(
      build_id => $buildid,
      );
  next unless($build);

  my @jobs = ();

  # This gets all Jobs associated with Events.
  # Reference Alignment uses Events.
  foreach my $e ($build->events) {
    print STDERR $e->lsf_job_id . ' ' .$e->class . "\n" if ($e->lsf_job_id && $verbose);
    push @jobs, $e->lsf_job_id;
  }

  # This gets all Jobs associated with Workflow Operation InstanceExecution.
  # Somatic pipeline is a workflow.
  foreach my $w ($build->workflow_instances) {
    foreach my $child ($w->ordered_child_instances) {
      my $wie = $child->current;
      print STDERR $wie->dispatch_identifier . ' ' . $child->name . "\n" if ($wie->dispatch_identifier && $verbose);
      push @jobs, $wie->dispatch_identifier if ($wie->dispatch_identifier);
    }
  }

  print join(',',@jobs);
}
