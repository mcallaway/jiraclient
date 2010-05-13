
use strict;
use warnings;
use Fcntl;
use Error;

package LSFSpool::BLAST;

sub new() {
  my $class = shift;
  my $self = {
    parent => shift,
    blastx => '/gsc/bin/blastxplus-2.2.23',
  };
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
  my $parameters = shift;
  my $spooldir = shift;
  # Note this input file may have LSB_JOBINDEX in it,
  # making it not a real filename, so don't test it with -f.
  my $inputfile = shift;

  throw Error::Simple("'parameters' unspecified")
    if (! defined $parameters);
  throw Error::Simple("given spool is not a directory: $spooldir")
    if (! -d $spooldir);

  $self->debug("action($parameters,$spooldir,$inputfile)\n");
  my $outputfile = "/tmp/" . $inputfile . "-output";
  $inputfile = $spooldir . "/" . $inputfile;

  # This is the action certified for this suite.
  # This is hard coded for security reasons.
  return "$self->{blastx} $parameters -query $inputfile -out $outputfile";
}

sub is_complete ($) {
  # Test if command completed correctly.
  # return 1 if complete, 0 if not
  use File::Basename;

  my $self = shift;
  my $infile = shift;

  if ( ! -f "$infile-output" or -s "$infile-output" == 0 ) {
    return 0;
  }

  my $inquery = $self->count_query(">", $infile);
  my $outquery = $self->count_query("Query=", "$infile-output");

  $self->debug("$inquery != $outquery\n");

  if ( $inquery != $outquery ) {
    return 0;
  }
  return 1;
}

sub count_query {

  my $self = shift;

  my $query = shift;
  my $filename = shift;

  $self->debug("count_query($query,$filename)\n");

  my $buf = '';
  my $buf_ref = \$buf;
  my $mode = Fcntl::O_RDONLY;

  local *FH ;
  sysopen FH, $filename, $mode or
    throw Error::Simple("can't open $filename: $!");

  local $/;

  my $size_left = -s FH;
  $self->debug("size $size_left\n");

  my $count = 0;
  while( $size_left > 0 ) {

    my $read_cnt = sysread( FH, ${$buf_ref}, $size_left, length ${$buf_ref} );

    throw Error::Simple("read error in file $filename: $!")
      unless( $read_cnt );

    my $last = 0;
    my $idx = 0;
    while ($idx != -1) {
      $idx = index(${$buf_ref},$query,$last);
      $last = $idx + 1;
      $count++ if ($idx != -1);
    }

    $size_left -= $read_cnt;
  }
  $self->debug("count_query($query,$filename) = $count\n");
  return $count;
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

