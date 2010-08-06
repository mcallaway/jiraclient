
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
  $self->{parameters} = $self->{parent}->{config}->{suite}->{parameters};
  bless $self, $class;
  return $self;
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
  my $inputfile = shift;

  my $parameters = $self->{parameters};

  $inputfile = $spooldir . "/" . $inputfile;

  throw Error::Simple("'parameters' unspecified")
    if (! defined $parameters);
  throw Error::Simple("given spool is not a directory: $spooldir")
    if (! -d $spooldir);

  # This is the action certified for this suite.
  return "cp $parameters $inputfile $inputfile-output";
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
