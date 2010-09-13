# Authenticate to GSC IMAP server
# Copyright (C) 2008 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Cyrus::IMAP::Admin::GSC;

=pod

=head1 NAME

GSCApp::Print::Barcode - Implements barcode printing methods.

=head1 SYNOPSIS

  use Cyrus::IMAP::Admin::GSC;

  $imap = Cyrus::IMAP::Admin::GSC->authenticate || die;

=head1 DESCRIPTION

=cut

use warnings;
use strict;

our $VERSION = '0.2';
my $pkg = __PACKAGE__;

use Cyrus::IMAP::Admin;
use IO::File;

=pod

=head1 METHODS

These methods interact with the IMAP daemon.

=over 4

=item authenticate

  $imap = Cyrus::IMAP::Admin::GSC->authenticate;

This method creates an authenticated connection to the IMAP daemon.
It returns the authenticated IMAP connection object on success and
C<undef> on failure.

This module should be installed in
F<gscimap:/usr/local/lib/perl5/site_perl/5.8.0/i386-linux-thread-multi/Cyrus/IMAP/Admin>.

=cut

sub authenticate
{
    my $class = shift;

    # set connection information
    my $server = 'localhost';
    my $adminuser = $class->user;
    my $rc = "/root/.cyrus";
    if (!-f $rc) {
        warn("$pkg: connection information file does not exist");
        return;
    }
    my $ph = IO::File->new("<$rc");
    if (!defined($ph)) {
        warn("$pkg: could not open password file: $!") ;
        return;
    }
    my $adminpw = $ph->getline;
    chomp($adminpw);
    $ph->close;

    # connect to server
    my $imap = Cyrus::IMAP::Admin->new($server);
    if (!$imap) {
        warn("$pkg: failed to create cyrus admin object");
        return;
    }

    # authenticate as admin user
    if (!$imap->authenticate
        (
            -user => $adminuser,
            -mechanism => "LOGIN",
            -password => $adminpw
         )
        || $imap->error)
    {
        warn("$pkg: unable to authenticate to $server: " . $imap->error);
        return;
    }

    return $imap;
}

my $user = 'cyrus';
sub user { return $user }

1;

__END__

=pod

=back

=head1 BUGS

Report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

Cyrus::IMAP(3), Cyrus::IMAP::Admin(3)

=head1 AUTHOR

David Dooling <ddooling@wustl.edu>

=cut
