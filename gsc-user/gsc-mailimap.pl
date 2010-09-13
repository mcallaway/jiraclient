#! /usr/bin/perl
# Create user IMAP directory.
# Copyright (C) 2008 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use warnings;
use strict;
use IO::File;
use Cyrus::IMAP::Admin::GSC;

my $pkg = 'gsc-mailimap';
my $version = '0.3';

# figure out what partition to use
#my @disks = qx(df -k /var/spool/cyrus*);
#if ($?) {
#    my $status = $? >> 8;
#    warn("$pkg: failed to get disk usage: $status ($?)");
#    exit(2);
#}
# get rid of header
#shift(@disks);
# find disk with most space
#my $max_avail = 0;
#my $partition;
#foreach my $disk (@disks) {
#    my ($mount, $avail) = (split(' ', $disk))[5, 3];
#    if ($avail > $max_avail) {
#        $partition = $mount;
#        $partition =~ s/^.*cyrus//;
#    }
#}

# connect to server
my $imap = Cyrus::IMAP::Admin::GSC->authenticate;
if (!defined($imap)) {
    warn("$pkg: failed to authenticate to cyrus IMAP server");
    exit(2);
}

# create user IMAP home
foreach my $login (@ARGV) {
    my $mbox = "user.$login";

    # see if it exists
    if ($imap->list($mbox)) {
        warn("$pkg: mailbox $mbox already exists");
        next;
    }

    # create the mailbox
#    if (!$imap->create($mbox, $partition)) {
    if (!$imap->create($mbox) ) {
        warn("$pkg: failed to create mailbox $mbox: " . $imap->error);
    }
}

# disconnect from server
#$imap->close;

# terminate program
exit(0);

=pod

=head1 NAME

gsc-mailimap - Create user IMAP directory

=head1 SYNOPSIS

B<gsc-mailimap> LOGIN[...]

=head1 DESCRIPTION

This script creates the mailbox for a new user.  It is meant to be
called from gsc-useradd.

=head1 OPTIONS

No options.

=back

=head1 BUGS

Please report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

=head1 AUTHOR

David Dooling <ddooling@wustl.edu>

=cut
