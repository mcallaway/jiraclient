
use strict;
use warnings;
use Fcntl;

package LSFSpool::WUBLASTX;

sub new() {
  my $class = shift;
  my $self = {
    parent => shift,
    blastx => '/gsc/scripts/bin/blastx',
  };
  $self->{parameters} = $self->{parent}->{config}->{suite}->{parameters},
  $self->{refdb} = $self->{parent}->{config}->{suite}->{refdb},
  return bless $self, $class;
}

sub logger {
  # Simple logging where logfile is set during startup
  # to either a file handle or STDOUT.
  my $self = shift;
  my $fh = $self->{parent}->{logfh};
  print $fh localtime() . ": @_";
}

sub debug($) {
  # Simple debugging.
  my $self = shift;
  $self->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}

sub action {
  my $self = shift;
  my $spooldir = shift;
  # Note this input file may have LSB_JOBINDEX in it,
  # making it not a real filename, so don't test it with -f.
  my $inputfile = shift;

  my $parameters = $self->{parameters};
  my $refdb = $self->{refdb};

  die "'parameters' unspecified"
    if (! defined $parameters);
  die "'refdb' unspecified"
    if (! defined $refdb);
  die "given spool is not a directory: $spooldir"
    if (! -d $spooldir);

  $self->debug("action($spooldir,$inputfile)\n");
  my $outputfile = $inputfile . "-output";
  $inputfile = $inputfile;

  # This is the action certified for this suite.
  # This is hard coded for security reasons.
  return "$self->{blastx} $refdb $inputfile $parameters -o $outputfile";
}

sub is_complete ($) {
  # Test if command completed correctly.
  # return 1 if complete, 0 if not
  use File::Basename;

  my $self = shift;
  my $infile = shift;

  if ( ! -f "$infile-output" or -s "$infile-output" == 0 ) {
    $self->debug("output file $infile-output is missing or empty\n");
    return 0;
  }

  my $char;
  my $pos = -1;
  my $found = 0;
  # Read output from the end for last line.
  open(FH,"<$infile-output") or die "Cannot open output file: $infile-output: $!";
  while (seek(FH,$pos--,2)) {
    read FH,$char,1;
    last if ($char eq "\n" and $found == 1);
    $found = 1 if ($char ne "\n");
  }
  my $last_line = <FH>;
  close(FH);
  print $last_line;

  # If file ends with WARNINGS ISSUED assume wu blast finished ok
  if ( $last_line !~ /^WARNINGS ISSUED/) {
    return 0;
  }

  return 1;
}

1;

__END__

=pod

=head1 NAME

BLAST - One of several possible Suite classes.

=head1 SYNOPSIS

  use LSFSpool::Suite;
  my $class = new LSFSpool::Suite->instantiate("BLAST",$self);

=head1 DESCRIPTION

This class represents the ability to run "blastx" as a "certified" program.
Here we define how blast is called, and how we validate the output.

=head1 CLASS METHODS

=over

=item new()

Instantiates the class.

=item logger($)

Trivial class' logger().  Log a line.

=item debug($)

Trivial class' debugging.  Log a line if debug is true.

=item run($)

Run an external command.

=item action()

Returns the command string for blastx.

=item is_complete()

Returns true if the input file has the same number of DNA sequence reads
as the corresponding output file.

=back

=head1 AUTHOR

Matthew Callaway (mcallawa@genome.wustl.edu)

=head1 COPYRIGHT

Copyright (c) 2010, Matthew Callaway. All Rights Reserved.  This module is free
software. It may be used, redistributed and/or modified under the terms of the
Perl Artistic License (see http://www.perl.com/perl/misc/Artistic.html)

=cut

