#!/usr/bin/env perl

use strict;
use warnings;
use English;

use Getopt::Long qw(:config auto_help);
use File::Basename;
use File::Path   qw(rmtree);
use Archive::Zip qw(:ERROR_CODES);
use Cwd 'abs_path';

use Bio::SeqIO;
use Pod::Usage;

use vars qw/ %options /;

our $VERSION = "0.3.0";

sub compress($) {
  # Compress a directory of batch files
  my $jobname = shift;
  return if (!defined($jobname));

  # Open a possibly pre-existing zip archive.
  my $zip = Archive::Zip->new();
  if (-f "$jobname.zip") {
    my $status = $zip->read("$jobname.zip");
    die "Error in archive $jobname.zip: $!" if (! $status == AZ_OK );
  }

  # Traverse a directory and add batch files to the zip.
  opendir(OD,$jobname) or die "Cannot enter dir $jobname: $!";
  for my $bfile (readdir OD) {
    $zip->addFile("$jobname/$bfile",basename($bfile));
  }
  closedir(OD);

  # Write the zip.
  unless ( $zip->overwriteAs("$jobname.zip") == AZ_OK ) {
    die "Error writing archive $jobname.zip: $!";
  }

  # Remove the temporary path.
  rmtree($jobname) or die "Cannot rmtree $jobname: $!";
  print "Compressed to $jobname.zip\n";
}

sub batch_input($$) {
  # Traverse a FASTA file, writing reads to output files and directories.
  my $fasta = shift;
  my $wait = shift;

  # We name our output after the input file.
  my $filename = basename($fasta);
  # Reads go in a batch file
  my $reads = 0;
  # Total reads read, to track progress through the input file
  my $totalreads = 0;
  # Bytes read
  my $sizeread = 0;
  # Batch file counter
  my $batch = 1;
  # A "job" is a set of batch files of size batches
  my $jobcount = 1;
  # A jobname is a directory or zip file containing batch files.
  my $jobname;
  # A batch file is a file containing reads.
  my $bfilename;

  # Input file
  my $ifasta;
  # Output file
  my $ofasta;

  # Size of the input FASTA file in bytes.
  my $totalsize = (stat $fasta)[7];

  # We use BIO::SeqIO to avoid shelling out to something like grep,
  # and this is a bit faster than my naive attempts at reading lines.
  $ifasta = Bio::SeqIO->new(-file => "<$fasta", -format => "fasta" );

  # Begin parsing input file
  while ( my $seq = $ifasta->next_seq() ) {

    $reads += 1;
    $totalreads += 1;
    $sizeread += length($seq);

    # Here we reach the size limit of a batch file.
    if ( $reads > $options{'reads'} ) {
      $reads = 1;
      $batch += 1;
      $ofasta->DESTROY() if defined($ofasta);
      undef $ofasta;
    }

    # Here we reach the job size limit.
    if ( defined $options{'batches'} and
          $batch > $options{'batches'} ) {
      # Compress the last job
      compress($jobname) if ($options{'compress'});
      # Start a new job directory.
      # We'll keep making jobs until EOF or "end" limit below.
      $batch = 1;
      $jobcount += 1;
      if ( $options{'end'} and
                   $jobcount > $options{'end'}) {
        print "Reached maximum number of batch files\n";
        return;
      }
    }

    # Wait to do work if a start mark is set, skipping to the given job.
    if (defined $options{'start'}) {
      if ($totalreads < $wait) {
        next;
      } else {
        undef $options{'start'};
      }
    }

    # Track output file.
    if (!defined($ofasta)) {

      # output path is
      # spooldir/spooldir-jobcount/spooldir-jobcount-batch
      if ($options{'output'}) {
        my $output = abs_path($options{'output'});
        $filename = basename $output;
        if (! -d $output and $filename ne $output) {
          printf "Create spooldir %s\n",$output;
          mkdir($output);
          chdir($output);
        }
        delete $options{'output'};
      }

      $jobname = sprintf "%s-%d",$filename,$jobcount;
      # Batch file name is a file containing reads.
      $bfilename = sprintf "%s-%d",$jobname,$batch;
      $bfilename = "$jobname/$bfilename";

      if ( -f $bfilename and ! $options{'force'}) {
        die "Cowardly refusing to clobber existing batchfile: $bfilename";
      }
      if ( -f $jobname and ! $options{'force'}) {
        die "Cowardly refusing to clobber existing job directory: $jobname";
      }
      if ( -f "$jobname.zip" and $options{'compress'} and
           ! $options{'force'}) {
        die "Cowardly refusing to clobber existing job archive: $jobname.zip";
      }
      if (! -d $jobname) {
        printf "Create job dir %s (%d/%d) with %d batches\n",$jobname,$jobcount,$options{'end'},$options{'batches'};
        mkdir($jobname) or die "Cannot mkdir $jobname: $!";
      }

      printf "Create batch file $bfilename with %d reads\n",$options{'reads'};
      open(OF, ">$bfilename") or die "Failed to open $bfilename: $!";
      $ofasta = Bio::SeqIO->new(-fh => \*OF, -format => "fasta" ) or die "Failed to make new SeqIO: $!";
    }

    # Write output
    # FIXME: Note that this may reformat the output from the input,
    # changing whitespace.  Do we care?
    $ofasta->write_seq( $seq ) or die "Failed to write to $bfilename: $!";
  }

  # After we've traversed the input file, close up file in progress.
  $ofasta->DESTROY() if defined($ofasta);
  undef $ofasta;
  compress($jobname) if ($options{'compress'});
}

sub version() {
  print "batch_fasta $VERSION\n";
}

sub main() {

  # Set defaults
  %options = (
    'reads' => 100,
    'batches' => 100,
    'end' => 0,
    'start' => undef,
    'compress' => undef,
    'output' => undef,
    'version' => undef,
  );

  GetOptions(
      'force' => \$options{'force'},
      'reads=i' => \$options{'reads'},
      'batches=i' => \$options{'batches'},
      'end=i' => \$options{'end'},
      'start=i' => \$options{'start'},
      'compress' => \$options{'compress'},
      'output=s' => \$options{'output'},
      'version' => \$options{'version'},
      );

  if ($options{'version'}) {
    version();
    exit 0;
  }
  if ($#ARGV != 0) {
    pod2usage();
  }
  my $fasta = $ARGV[0];
  if ( ! -f $fasta ) {
    die "No such file: $fasta";
  }

  # This is a convenience.  We want to be able to continue
  # batching after interruption.
  my $wait = 0;

  if ($options{'start'} and $options{'end'} and
      $options{'end'} <= $options{'start'}) {
    die "The 'end' must be greater than the 'start' job";
  }

  if ($options{'start'}) {
    $wait = $options{'start'} * $options{'reads'} * $options{'batches'};
    print "Start at job $options{'start'} = $wait reads\n";
  }

  batch_input($fasta,$wait);
  print "Done\n";
}

main();

__END__
=pod

=head1 NAME

  batch_fasta - Break a FASTA file into smaller chunks.

=head1 SYNOPSIS

  batch_fasta [--force] [--reads N] [--batches N] [--start N] [--end N] [--compress] [--output DIR] [--version] <fasta>

=head1 OPTIONS

  --force        Overwrite existing files if present.
  --reads   <N>  Number of reads per batch file.
  --batches <N>  Number of batch files per jobs.
  --start   <N>  Skip to the first read of job N.
  --end     <N>  Stop after job N.
  --compress     Put output batch jobs to zip archives.
  --output <DIR> Specify an output path.
  --version      Display version information

=head1 DESCRIPTION

This is a simple program to batch a FASTA formatted ascii text
file into smaller chunks with a logical naming scheme.
Output will either be smaller FASTA files in subdirectories,
or zip archives containing those smaller FASTA files.

=head1 EXAMPLES

s_7_1_for_bwa_input.pair_a is a FASTA file with 18 million reads.

  # ls -lh s_7_1_for_bwa_input.pair_a
  -rw-rw-r-- 1 user users 2.0G 2009-12-15 12:45 s_7_1_for_bwa_input.pair_a

We want to break it up into manageble chunks for processing with BLASTX.

  # mkdir seq-s_7_1_for_bwa_input.pair_a
  # cd $!
  # batch_fasta.pl --reads 500 --batches 100 ../s_7_1_for_bwa_input.pair_a

This will produce subdirectories under the top level directory,
seq-s_7_1_for_bwa_input.pair_a that each contain 100 batch files
of 500 reads each.

Your directory will look like:

  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-1/s_7_1_for_bwa_input.pair_a-1-1
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-1/s_7_1_for_bwa_input.pair_a-1-2
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-1/s_7_1_for_bwa_input.pair_a-1-3
  ...
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-1/s_7_1_for_bwa_input.pair_a-1-M
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-2
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-2/...
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-3
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-3/...
  ...
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-N
  seq-s_7_1_for_bwa_input.pair_a/s_7_1_for_bwa_input.pair_a-N/...

You can now process this B<spool directory> using B<lsf_spool.pl>

  # lsf_spool.pl -p seq-s_7_1_for_bwa_input.pair_a


=head1 KNOWN ISSUES

BIO::SeqIO->write_seq() does some formatting such that batchfiles are not
exactly the same as input files.  Changes are whitespace, and I'm not sure
we care.

=head1 AUTHOR

  Matthew Callaway

=head1 COPYRIGHT

  Copyright 2010 Matthew Callaway

  This program is free software; you can redistribute it and/or modify it
  under the same terms as Perl itself.
