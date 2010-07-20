
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
  $self->{parameters} = $self->{parent}->{config}->{suite}->{parameters};
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

  throw Error::Simple("'parameters' unspecified")
    if (! defined $parameters);
  throw Error::Simple("given spool is not a directory: $spooldir")
    if (! -d $spooldir);

  $self->debug("action($spooldir,$inputfile)\n");
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

  # blastx creates output files with some number of reads in them but it may
  # include a given read more than once, or not at all.  So, we just ensure
  # non-empty output and trust that if blastx exits zero, then we're ok.
  my $inquery = $self->count_query(">", $infile);
  if (! defined $inquery ) {
    $self->debug("inquery is undefined\n");
    return 0;
  }

  if ( ! -f "$infile-output" or -s "$infile-output" == 0 ) {
    $self->debug("output file $infile-output is missing or empty\n");
    return 0;
  }

  my $outquery = $self->read_output("$infile-output");

  if (! defined $outquery ) {
    $self->debug("outquery is undefined\n");
    return 0;
  }

  $self->debug("is_complete: $inquery ?= $outquery\n");

  if ( $inquery != $outquery ) {
    return 0;
  }

  return 1;
}

sub read_output {
  my $self = shift;
  my $filename = shift;

  my $parameters = $self->{parameters};

  $self->debug("read_output($filename)\n");
  my $format = 0;

  if ($parameters =~ m/.*outfmt\s\"(.*)\"/) {
    my @toks = split(/ /,$1);
    $format = $toks[0];
  } else {
    # no format specified, use the default
    $format = 0;
  }

  $self->debug("output format: $format\n");
  if ($format == 7) {
    return $self->outfmt_7($filename);
  } elsif ($format == 0) {
    return $self->outfmt_0($filename);
  } else {
    throw Error::Simple("Unsupported blastx output format: $format");
  }
}

sub outfmt_0 {
  my $self = shift;
  my $filename = shift;
  return $self->count_query("Query=",$filename);
}

sub outfmt_7 {

  my $self = shift;
  my $filename = shift;

  my $buf = '';
  my $buf_ref = \$buf;
  my $mode = Fcntl::O_RDONLY;

  local *FH ;
  local $/;

  # Return 0 so caller gets 'incomplete'.
  sysopen FH, $filename, $mode or
    return 0;

  # Seek to end of file minus some and read it.
  # Assumes that one line will fit into "blocksize".
  my $blocksize = 100;
  sysseek FH, -$blocksize, 2 or return 0;
  sysread FH, ${$buf_ref}, $blocksize or return 0;
  close FH ;

  my $res;
  if ($buf =~ m/processed (\d+) queries/) {
    $res = $1;
  }
  return $res;
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

  # Return 0 so caller gets 'incomplete'.
  sysopen FH, $filename, $mode or
    return 0;

  local $/;

  my $size_left = -s FH;
  $self->debug("size $size_left\n");

  my $count = 0;
  while( $size_left > 0 ) {

    my $read_cnt = sysread( FH, ${$buf_ref}, $size_left, length ${$buf_ref} );

    return 0 unless( $read_cnt );

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
  close(FH);
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

