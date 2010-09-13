#! /usr/bin/perl
# Archive user mail.
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
use Getopt::Long;
use IO::File;
use IO::Handle;
use Cyrus::IMAP::Admin::GSC;

# set up script
my $pkg = 'gsc-mailarchive';
my $version = '0.5';

my ($delete, $help, $print_version);
unless (&GetOptions('delete' => \$delete,
                    'help' => \$help,
                    'version' => \$print_version))
{
    STDERR->print("Try ``$pkg --help'' for more information.\n");
    exit(1);
}
if ($print_version) {
    STDOUT->print("$pkg $version\n");
    exit(0);
}
if ($help) {
    &usage();
    exit(0);
}

# no buffering
STDOUT->autoflush(1);

# get login
my $login;
if (@ARGV) {
    $login = $ARGV[0];
}
else {
    until ($login) {
        STDOUT->print("$pkg: please enter login: ");
        $login = STDIN->getline;
        chomp($login);
    }
}

# set restrictive umask
umask(0077);

# find their mail directory
my ($mdir) = glob("/var/spool/cyrus*/user/$login");
if (!$mdir) {
    warn("$pkg: failed to find user mail directory");
    exit(0);
}
if (!-d $mdir) {
    warn("$pkg: user mail is not a directory: $mdir");
    exit(2);
}

# see if we should archive or delete
if ($delete) {
    STDOUT->print("$pkg: delete $mdir? (y/n) [n] ");
    my $ans = STDIN->getline;
    chomp($ans);
    if ($ans !~ m/^[Yy]/) {
        undef($delete);
    }
}
if (!$delete) {
    my $tar = "/var/spool/cyrus/tmp/$login.tar.gz";
    # tar up the files
    my $tar_cmd = "cd $mdir/.. && tar -c -z -f $tar $login";
    if (system($tar_cmd) != 0) {
        warn("$pkg: failed to tar user mail: $tar_cmd");
        exit(2);
    }

    # copy the file
    my $dest = 'linuscs65:/archive/archive/account_archive/mail';
    my @rcp = ('scp', $tar, $dest);
    if (system(@rcp) != 0) {
        warn("$pkg: failed to copy tar file: @rcp");
        exit(2);
    }

    # remove the tar
    if (!unlink($tar)) {
        warn("$pkg: failed to remove tar file: $tar: $!");
    }
}

# connect to imap server
my $imap = Cyrus::IMAP::Admin::GSC->authenticate;
if (!defined($imap)) {
    warn("$pkg: failed to connect to IMAP server");
    exit(2);
}

# grant cyrus user acl on user mail
my $mbox = "user.$login";
my $status = 0;
if (!$imap->setacl($mbox, Cyrus::IMAP::Admin::GSC->user => 'c')) {
    warn("$pkg: failed to set acl on mailbox $mbox: " . $imap->error);
    $status = 2;
}
# delete the mail
if (!$imap->delete($mbox)) {
    warn("$pkg: failed to delete mailbox $mbox: " . $imap->error);
    $status = 2;
}

# terminate program
exit($status);

sub usage
{
    my $usage = <<"EOF";
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -d,--delete    delete mail rather than archive
  -h,--help      print this message and exit
  -v,--version   print version number and exit

This is meant to be called from gsc-userdel to archive user mail.

EOF

    print($usage);
    return 1;
}

=pod

=head1 NAME

gsc-mailimap - Create user IMAP directory

=head1 SYNOPSIS

  B<gsc-mailarchive> [OPTIONS]... [LOGIN]

=head1 DESCRIPTION

Archive and remove a user's mail from the system.  This script is
meant to be called from gsc-userdel.

=head1 OPTIONS

If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

=over 4

=item --delete

Delete user mail rather than archive.

=item --help

Display a brief description and listing of all available options.

=item --version

Output version information and exit.

=item --

Terminate option processing.  This option is useful when file names
begin with a dash (-).

=back

=head1 BUGS

Please report bugs to <software@genome.wustl.edu>.

=head1 SEE ALSO

=head1 AUTHOR

David Dooling <ddooling@wustl.edu>

=cut
