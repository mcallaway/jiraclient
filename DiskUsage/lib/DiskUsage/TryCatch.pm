# Copyright (c) 2008 by David Golden. All rights reserved.
# Licensed under Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License was distributed with this file or you may obtain a 
# copy of the License from http://www.apache.org/licenses/LICENSE-2.0

#package Exception::Class::TryCatch;
package DiskUsage::TryCatch;

$VERSION     = '1.12';
@ISA         = qw (Exporter);
@EXPORT      = qw ( catch try );
@EXPORT_OK   = qw ( caught );

use 5.005; # Aiming for same as Exception::Class
#use warnings -- not supported in Perl 5.5, darn
use strict;
use Exception::Class;
use Exporter ();

my @error_stack;

#--------------------------------------------------------------------------#
# catch()
#--------------------------------------------------------------------------#

sub catch(;$$) {
    my $e;
    my $err = @error_stack ? pop @error_stack : $@;
    if ( UNIVERSAL::isa($err, 'Exception::Class::Base' ) ) {
        $e = $err;
    } 
    elsif ($err eq '') {
        $e = undef;
    }
    else {
        # use error message or hope something stringifies
        $e = Exception::Class::Base->new( "$err" );
    }
    unless ( ref($_[0]) eq 'ARRAY' ) { 
        $_[0] = $e;
        shift;
    }
    if ($e) {
        if ( defined($_[0]) and ref($_[0]) eq 'ARRAY' ) {
            $e->rethrow() unless grep { $e->isa($_) } @{$_[0]};
        }
    }
    return wantarray ? ( $e ? ($e) : () ) : $e;
}

*caught = \&catch;

#--------------------------------------------------------------------------#
# try()
#--------------------------------------------------------------------------#

sub try($) {
    my $v = shift;
    push @error_stack, $@;
    return ref($v) eq 'ARRAY' ? @$v : $v if wantarray;
    return $v;
}

1;

__END__

=begin wikidoc

= NAME

Exception::Class::TryCatch - Syntactic try/catch sugar for use with Exception::Class

= VERSION

This documentation describes version %%VERSION%%.

= SYNOPSIS

    use Exception::Class::TryCatch;
    
    # simple usage of catch()
    
    eval { Exception::Class::Base->throw('error') };
    catch my $err and warn $err->error;

    # catching only certain types or else rethrowing
    
    eval { Exception::Class::Base::SubClass->throw('error') };
    catch( my $err, ['Exception::Class::Base', 'Other::Exception'] )
        and warn $err->error; 
    
    # catching and handling different types of errors
    
    eval { Exception::Class::Base->throw('error') };
    if ( catch my $err ) {
        $err->isa('this') and do { handle_this($err) };
        $err->isa('that') and do { handle_that($err) };
    }
    
    # use "try eval" to push exceptions onto a stack to catch later
    
    try eval { 
        Exception::Class::Base->throw('error') 
    };
    do {
        # cleanup that might use "try/catch" again
    };
    catch my $err; # catches a matching "try"

= DESCRIPTION

Exception::Class::TryCatch provides syntactic sugar for use with
[Exception::Class] using the familiar keywords {try} and {catch}.  Its
primary objective is to allow users to avoid dealing directly with {$@} by
ensuring that any exceptions caught in an {eval} are captured as
[Exception::Class] objects, whether they were thrown objects to begin with or
whether the error resulted from {die}.  This means that users may immediately
use {isa} and various [Exception::Class] methods to process the exception. 

In addition, this module provides for a method to push errors onto a hidden
error stack immediately after an {eval} so that cleanup code or other error
handling may also call {eval} without the original error in {$@} being lost.

Inspiration for this module is due in part to Dave Rolsky's
article "Exception Handling in Perl With Exception::Class" in
~The Perl Journal~ (Rolsky 2004).

The {try/catch} syntax used in this module does not use code reference
prototypes the way the [Error.pm|Error] module does, but simply provides some
helpful functionality when used in combination with {eval}.  As a result, it
avoids the complexity and dangers involving nested closures and memory leaks
inherent in [Error.pm|Error] (Perrin 2003).  

Rolsky (2004) notes that these memory leaks may not occur in recent versions of
Perl, but the approach used in Exception::Class::TryCatch should be safe for all
versions of Perl as it leaves all code execution to the {eval} in the current
scope, avoiding closures altogether.

= USAGE

== {catch}

    # zero argument form
    my $err = catch;

    # one argument forms
    catch my $err;
    my $err = catch( [ 'Exception::Type', 'Exception::Other::Type' ] );

    # two argument form
    catch my $err, [ 'Exception::Type', 'Exception::Other::Type' ];

Returns an {Exception::Class::Base} object (or an object which is a subclass of
it) if an exception has been caught by {eval}.  If no exception was thrown, it
returns {undef} in scalar context and an empty list in list context.   The
exception is either popped from a hidden error stack (see {try}) or, if the
stack is empty, taken from the current value of {$@}.

If the exception is not an {Exception::Class::Base} object (or subclass
object), an {Exception::Class::Base} object will be created using the string
contents of the exception.  This means that calls to {die} will be wrapped and
may be treated as exception objects.  Other objects caught will be stringfied
and wrapped likewise.  Such wrapping will likely result in confusing stack
traces and the like, so any methods other than {error} used on 
{Exception::Class::Base} objects caught should be used with caution.

{catch} is prototyped to take up to two optional scalar arguments.  The single
argument form has two variations.  

* If the argument is a reference to an array,
any exception caught that is not of the same type (or a subtype) of one
of the classes listed in the array will be rethrown.  
* If the argument is not a reference to an array, {catch} 
will set the argument to the same value that is returned. 
This allows for the {catch my $err} idiom without parentheses.

In the two-argument form, the first argument is set to the same value as is
returned.  The second argument must be an array reference and is handled 
the same as as for the single argument version with an array reference, as
given above.

== {caught} (DEPRECATED)

{caught} is a synonym for {catch} for syntactic convenience.

NOTE: Exception::Class version 1.21 added a "caught" method of its own.  It
provides somewhat similar functionality to this subroutine, but with very
different semantics.  As this class is intended to work closely with
Exception::Class, the existence of a subroutine and a method with the same name
is liable to cause confusion and this method is deprecated and may be removed
in future releases of Exception::Class::TryCatch.

This method is no longer exported by default.

== {try}

    # void context
    try eval {
      # dangerous code
    };
    do {
      # cleanup code can use try/catch
    };
    catch my $err;
 
    # scalar context
    $rv = try eval { return $scalar };

    # list context
    @rv = try [ eval { return @array } ];

Pushes the current error ({$@}) onto a hidden error stack for later use by
{catch}.  {try} uses a prototype that expects a single scalar so that it can
be used with eval without parentheses.  As {eval { BLOCK }} is an argument
to try, it will be evaluated just prior to {try}, ensuring that {try}
captures the correct error status.  {try} does not itself handle any errors --
it merely records the results of {eval}. {try { BLOCK }} will be interpreted
as passing a hash reference and will (probably) not compile. (And if it does,
it will result in very unexpected behavior.)

Since {try} requires a single argument, {eval} will normally be called
in scalar context.  To use {eval} in list context with {try}, put the 
call to {eval} in an anonymous array:  

  @rv = try [ eval {return @array} ];

When {try} is called in list context, if the argument to {try} is an array
reference, {try} will dereference the array and return the resulting list.

In scalar context, {try} passes through the scalar value returned
by {eval} without modifications -- even if that is an array reference.

  $rv = try eval { return $scalar };
  $rv = try eval { return [ qw( anonymous array ) ] };

Of course, if the eval throws an exception, {eval} and thus {try} will return
undef.

{try} must always be properly bracketed with a matching {catch} or unexpected
behavior may result when {catch} pops the error off of the stack.  {try} 
executes right after its {eval}, so inconsistent usage of {try} like the
following will work as expected:

    try eval {
        eval { die "inner" };
        catch my $inner_err
        die "outer" if $inner_err;
    };
    catch my $outer_err;
    # handle $outer_err;
    
However, the following code is a problem:

    # BAD EXAMPLE
    try eval {
        try eval { die "inner" };
        die $@ if $@;
    };
    catch my $outer_err;
    # handle $outer_err;
    
This code will appear to run correctly, but {catch} gets the exception
from the inner {try}, not the outer one, and there will still be an exception
on the error stack which will be caught by the next {catch} in the program, 
causing unexpected (and likely hard to track) behavior.

In short, if you use {try}, you must have a matching {catch}.  The problem
code above should be rewritten as:

    try eval {
        try eval { die "inner" };
        catch my $inner_err;
        $inner_err->rethrow if $inner_err;
    };
    catch my $outer_err;
    # handle $outer_err;

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted through the web interface at 
[http://rt.cpan.org/Dist/Display.html?Queue=Exception-Class-TryCatch]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= REFERENCES

0 perrin. (2003), "Re: Re2: Learning how to use the Error module by example",
(perlmonks.org), Available: http://www.perlmonks.org/index.pl?node_id=278900
(Accessed September 8, 2004).
0 Rolsky, D. (2004), "Exception Handling in Perl with Exception::Class",
~The Perl Journal~, vol. 8, no. 7, pp. 9-13

= SEE ALSO

* [Exception::Class]
* [Error] -- but see (Perrin 2003) before using

= AUTHOR

David A. Golden (DAGOLDEN)

= COPYRIGHT AND LICENSE

Copyright (c) 2004-2008 by David A. Golden. All rights reserved.

Licensed under Apache License, Version 2.0 (the "License").
You may not use this file except in compliance with the License.
A copy of the License was distributed with this file or you may obtain a 
copy of the License from http://www.apache.org/licenses/LICENSE-2.0

Files produced as output though the use of this software, shall not be
considered Derivative Works, but shall be considered the original work of the
Licensor.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=end wikidoc

=cut

