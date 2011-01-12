#
# This is a "Suite" Factory, where a Suite is a class representative of a
# particular program that we want LSFSpool to run under LSF.  Each Suite has a
# program to run, including all parameters, as well as an is_complete function,
# providing a test for whether or not this program has completed.
#
# All Suites are defined in LSFSpool/${NAME}.pm.

package LSFSpool::Suite;

use LSFSpool::NCBIBLASTX;
use LSFSpool::WUBLASTX;
use LSFSpool::Trivial;

sub instantiate() {
  my $self     = shift;
  my $type     = shift;
  my $location = "LSFSpool/$type.pm";
  my $class    = "LSFSpool::$type";

  require $location;
  return $class->new(@_);
}

1;

__END__

=pod

=head1 NAME

LSFSpool::Suite - A Suite Factory

=head1 SYNOPSIS

my $class = new LSFSpool::Suite->instantiate("NAME",$self);

=head1 DESCRIPTION

This is a class that generates one of several possible "Suites" which describe
a particular program that may be run via LSF.  There is one Suite per command,
eg. blastx.  We use these Suite classes to define what is a "certified" program
that can be run, to avoid giving the user the ability to run anything they
want to.

=head1 CLASS METHODS

=over

=item instantiate("NAME",$self)

Returns an instance of the named class.  The first argument is the name
of the Suite class to instantiate, eg. NCBIBLASTX.  The second argument is
the caller's $self.  We use $self to be able to refer to configuration items.

=back

=head1 AUTHOR

Matthew Callaway (mcallawa@genome.wustl.edu)

=head1 COPYRIGHT

Copyright (c) 2010, Matthew Callaway. All Rights Reserved.  This module is free
software. It may be used, redistributed and/or modified under the terms of the
Perl Artistic License (see http://www.perl.com/perl/misc/Artistic.html)

=cut


