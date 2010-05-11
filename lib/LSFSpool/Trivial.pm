
#
# This is a trivial suite for unit testing.
#

package LSFSpool::Trivial;

use warnings;
use strict;
use Error;

sub new() {
  my $class = shift;
  my $self = {
    parent => shift,
  };
  bless $self, $class;
  return $self;
}

sub logger {
  # Simple logging where logfile is set during startup
  # to either a file handle or STDOUT.
  my $self = shift;
  my $fh = $self->{parent}->{logfile};
  print $fh localtime() . ": @_";
}

sub debug($) {
  # Simple debugging.
  my $self = shift;
  $self->logger("DEBUG: @_")
    if ($self->{parent}->{debug});
}

sub run {
  my $self = shift;
  my $command = shift;
  # Add trailing pipe for reading output
  $self->debug("run($command)\n");
  open(COM,"$command |") or
    throw Error::Simple("failed to exec certified command: $command: $!");
  my $output;
  while (<COM>) {
    $output .= $_;
  }
  close(COM);
  my $rc = $? >> 8;
  $self->debug("exit $rc\n");
  throw Error::Simple("command exits non-zero: $command: $!") if ($rc);
  return $rc;
}

sub action {
  my $self = shift;
  my $spooldir = shift;
  my $inputfile = shift;
  $inputfile = $spooldir . "/" . $inputfile;

  throw Error::Simple("given spool is not a directory: $spooldir")
    if (! -d $spooldir);
  throw Error::Simple("given input file is not a file: $inputfile")
    if (! -f $inputfile);

  # This is the action certified for this suite.
  my $command = "cp $inputfile $inputfile-output";
  $self->run($command);
}

sub is_complete {
  # Test if command completed correctly.
  # return 0 if invalid, 1 if valid
  use File::Compare;

  my $self = shift;
  my $infile = shift;

  my $result = compare($infile,"$infile-output");
  if ( $result != 0 ) {
    $self->debug("Input file $infile returns incomplete: $result\n");
    return 0;
  }

  return 1;
}

1;

__END__

=pod

=head1 NAME

LSFSpool::Trivial - A trivial LSFSpool command Suite implementing cp(1).

=head1 SYNOPSIS

  use LSFSpool::Trivial
  my $suite = new LSFSpool::Trivial

=head1 DESCRIPTION

This simple command suite allows for unit testing of LSFSpools spooling
mechanism.

=head1 CLASS METHODS

=over

=item new()

Instantiates the class.

=item logger()

Trivial class' logger().

=item debug()

Trivial class' debugging.

=item run()

Run an external command.

=item action()

Performs a simple "cp $inputfile ${inputfile}-output" in the current spooldir.

=item is_complete()

Returns true if the input file matches the outputfile.

=back

=head1 AUTHOR

Matthew Callaway (mcallawa@genome.wustl.edu)

=head1 COPYRIGHT

Copyright (c) 2010, Matthew Callaway. All Rights Reserved.  This module is free
software. It may be used, redistributed and/or modified under the terms of the
Perl Artistic License (see http://www.perl.com/perl/misc/Artistic.html)

=cut
