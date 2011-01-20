#! /usr/bin/env perl

use strict;
use warnings;
use File::Basename qw/basename/;
use above 'Genome';
use Data::Dumper;

if (! scalar @ARGV) {
  print "Usage: " . basename $0 . " <build ids>\n";
  exit 1;
}

foreach my $buildid (@ARGV) {
  my $build = Genome::Model::Build->get(
      build_id => $buildid,
      );
  next unless($build);

  my @jobs = ();

  # This gets all Jobs associated with Events.
  # Reference Alignment uses Events.
  foreach my $e ($build->events) {
    push @jobs, $e->lsf_job_id if ($e->lsf_job_id);
  }

  # This gets all Jobs associated with Workflow Operation InstanceExecution.
  # Somatic pipeline is a workflow.
  foreach my $w ($build->workflow_instances) {
    foreach my $child ($w->ordered_child_instances) {
      my $wie = $child->current;
      push @jobs, $wie->dispatch_identifier if ($wie->dispatch_identifier);
    }
  }

  print join(',',@jobs);
}
