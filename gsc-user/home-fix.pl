#! /gsc/bin/perl
# Fix references to a user home directory path.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

use warnings;                   # -w
use strict;                     # apply all restrictions

use File::Copy;
use IO::Dir;
use IO::Handle;
use Sys::Hostname;

# import all the GSC and database stuff
use GSCApp;

# set up App information
App->pkg_name('home-fix');
App->title('Fix references to a user home directory');
App->version('0.3');
App->author('David Dooling');
App->author_email('ddooling@watson.wustl.edu');
App->synopsis(lc(App->title));
App->usage_head('[OPTIONS]... [LOGIN]');

# process command line options
my $test;
App->get_options
(
    test =>
    {
        option => '--test',
        message => 'do not actually change anything',
        action => \$test
    }
);

# no buffering
STDOUT->autoflush;

# see if root is running the script
if ($< == 0) {
    warn("running as root") if App::Debug->level;
}
else {
    warn("you must run this script as root");
    exit(1);
}

# make sure they are on homesrv
my $host = hostname;
# unqualify name
$host =~ s{\..*}{};
if ($host eq 'homesrv') {
    warn("running on $host") if App::Debug->level;
}
else {
    warn("you must run this script on homesrv");
    exit(1);
}

# make sure login was specified
my ($login) = @ARGV;
if ($login) {
    warn("set login to $login") if App::Debug->level;
}
else {
    # get the login to be changed
    $login = &prompt("enter login name");
}

# get old and new path
my $new = "/gscuser/$login";
# try the passwd file
my ($uid, $gid, $old) = (getpwnam($login))[2,3,7];
if (!$old || !$uid) {
    # try to get it from netmgr
    my $pw = qx{rsh netmgr grep "'^$login:'" /etc/passwd};
    if ($? == 0 && $pw) {
        my ($tuid, $tgid, $told) = (split(m{:}, $pw))[2,3,5];
        $uid ||= $tuid;
        $gid ||= $tgid;
        $old ||= $told;
    }
}
# make sure passwd file was not updated yet
if ($old && $old !~ m{home\d+/(watson|crick)}) {
    undef($old);
}
if (!$old) {
    # try to determine from gscuser link
    $old = readlink($new);
    if ($old) {
        # replace gschome with watson
        $old =~ s{gschome/(\d+)}{home$1/watson};
        print(App->pkg_name . ":previous home directory $old? (y/n) [n] ");
        my $ans = STDIN->getline;
        if ($ans !~ m{^[Yy]}) {
            undef($old);
        }
    }
}
if ($old) {
    warn("determined old home directory to be $old") if App::Debug->level;
}
else {
    # prompt the user
    warn("failed to determine old home directory");
    $old = &prompt("enter old home directory");
}
# make sure we got a uid
if ($uid) {
    warn("determined uid for $login:$uid") if App::Debug->level;
}
else {
    # prompt the user
    warn("failed to determine uid");
    $uid = &prompt("enter uid for $login");
}
# set gid to gsc if not yet set
$gid ||= 10001;

# make sure old home directory looks right
if ($old =~ m{gsc}) {
    warn("old home directory looks like a new home directory:$old");
    $old = &prompt("enter old home directory");
}

# open the log file
my $log = "/tmp/" . App->pkg_name . "_$login.log";
my $log_fh = IO::File->new(">$log");
if (defined($log_fh)) {
    warn("opened log file for writing") if App::Debug->level;
}
else {
    warn("failed to open log file for writing:$!");
    exit(1);
}

# recursively descend through directory structure, fixing references
&rfix($new, $old, $new);

# close log file
$log_fh->close;

# do not make any changes on netmgr if testing
if ($test) {
    exit(0);
}

# update the user home directory on netmgr
if (system('rsh', 'netmgr', 'usermod', '-d', $new, $login) == 0) {
    warn("updated $login home directory on netmgr to $new")
        if App::Debug->level;
}
else {
    warn("failed to update $login home directory on netmgr to $new");
    exit(1);
}

# push the changes out on netmgr
if (system('rsh', 'netmgr', 'cd /var/yp && make') == 0) {
    warn("pushed changes out on netmgr") if App::Debug->level;
}
else {
    warn("failed to push changed out on netmgr");
    exit(1);
}

# terminate program
exit(0);

# prompt a user for input and get it
sub prompt
{
    my ($msg) = @_;
    my $input;
    until ($input) {
        print(App->pkg_name . ":$msg: ");
        $input = STDIN->getline;
        chomp($input);
    }
    return $input;
}

# do the fixin
sub rfix
{
    my ($dir, $old, $new) = @_;

    # open the directory
    my $dh = IO::Dir->new($dir);
    if (defined($dh)) {
        warn("opened directory $dir") if App::Debug->level > 4;
    }
    else {
        warn("failed to open directory $dir");
        return;
    }

    while (defined(my $entry = $dh->read)) {
        next if $entry eq '.' || $entry eq '..';
        my $path = "$dir/$entry";
        if (-l $path) {
            # get where the link points to
            my $target = readlink($path);
            if ($target) {
                warn("read link $path:$target") if App::Debug->level > 2;
            }
            else {
                # can not fix
                next;
            }
            # see if target contains old
            if ($target =~ s/$old/$new/) {
                if ($test) {
                    warn("fix symlink:$path -> $target\n");
                    next;
                }
                # remove old link
                if (unlink($path)) {
                    &log("removed symlink:$path");
                }
                else {
                    &log("failed to remove symlink:$path");
                    next;
                }
                # create new link
                if (symlink($target, $path)) {
                    &log("create new symlink:$path -> $target");
                }
                else {
                    &log("failed to create new symlink:$path -> $target");
                }
                # fix the ownership of link
                # builtin chown will not change symlinks
                if (system('chown', '-h', "$uid:$gid", $path) == 0) {
                    warn("chowned symlink:$path") if App::Debug->level > 2;
                }
                else {
                    &log("failed to chown symlink:$path");
                }
            }
        }
        elsif (-d $path) {
            # recurse
            &rfix($path, $old, $new);
        }
        elsif (-f _) {
            # see if it has anything in it and is text
            if (-s _ && -T _) {
                # see if it has a reference to old
                my $rv = system('/gsc/bin/grep', '-q', $old, $path);
                # see if there was a match
                if ($rv == 0) {
                    # {{{ fix it
                    # get owner, group, and mode of file
                    my @stat = stat($path);
                    if (@stat) {
                        warn("statted $path") if App::Debug->level > 3;
                    }
                    else {
                        &log("failed stat on $path");
                        next;
                    }
                    my ($fmode, $fuid, $fgid) = @stat[2,4,5];

                    # do not do anything if testing
                    if ($test) {
                        warn("fix file:$path\n");
                        next;
                    }

                    # save old file
                    my $oldpath = $path . App->pkg_name;
                    # make sure path is unique
                    while (-e $oldpath) { $oldpath .= 'x' }
                    if (move($path, $oldpath)) {
                        warn("moved $path to $oldpath")
                            if App::Debug->level > 3;
                    }
                    else {
                        &log("failed to move $path to $oldpath");
                        next;
                    }

                    # use sed to fix file
                    my $sed = "/gsc/bin/sed 's,$old,$new,g' '$oldpath' >'$path'";
                    if (system($sed) == 0) {
                        warn("did sed substitution on $path")
                            if App::Debug->level > 3;
                    }
                    else {
                        # try to move back
                        unlink($path);
                        move($oldpath, $path);
                        &log("failed to sed fix $path: $sed");
                        next;
                    }

                    # make sure file has proper mode
                    if (chmod($fmode & 07777, $path)) {
                        warn("chmoded $path") if App::Debug->level > 3;
                    }
                    else {
                        &log("failed to chmod $path");
                        next;
                    }

                    # make sure file has proper ownership
                    if (chown($fuid, $fgid, $path)) {
                        warn("chowned $path") if App::Debug->level > 3;
                    }
                    else {
                        &log("failed to chown $path");
                        next;
                    }

                    # remove original
                    if (unlink($oldpath)) {
                        warn("removed $oldpath") if App::Debug->level > 3;
                    }
                    else {
                        &log("failed to remove $oldpath");
                    }

                    # record the fix
                    &log("fixed file:$path");
                    # }}}
                }
            }
        }
    }
    $dh->close;

    return 1;
}

# log and print out error
sub log
{
    my ($msg) = @_;
    warn($msg) if App::Debug->level;
    return $log_fh->print("$msg\n");
}

=pod

=head1 NAME

home-fix - fix references to home directory path.

=head1 SYNOPSIS

B<home-fix> [OPTIONS]... [LOGIN]

=head1 DESCRIPTION

This script traverses a user's home directory and fixes hard-coded
references to the users home directory in ASCII files.  It also fixes
symbolic links that point to the users home directory.

If no LOGIN is specified, the script uses the login of the user
running the script, unless that user is C<root>.  If the user is root,
then the script prompts for the login.

This script should be run before the user home directory is updated in
the F<passwd> file, but after the home directory has been moved (if
necessary).

Any operations the script does are recorded in a log file in F</tmp>
named F<home-fix_LOGIN.log>.

This script does not fix the Mozilla profile problem.

It is recommended that you run this script as the user whose home
directory is being fixed on homesrv.

=head1 OPTIONS

If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

=over 4

=item --help

Display a brief description and listing of all available options.

=item --version

Output version information and exit.

=item --

Terminate option processing.  This option is useful when file names
begin with a dash (-).

=back

=head1 BUGS

Please report bugs to <software@watson.wustl.edu>.

=head1 SEE ALSO

App(3), GSCApp(3)

=head1 AUTHOR

David Dooling <ddooling@watson.wustl.edu>

=cut

# $Header$
