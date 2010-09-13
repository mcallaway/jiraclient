#! /gsc/bin/perl
# clean up passwd and shadow file
# Copyright (C) 2003 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

use warnings;                   # -w
use strict;                     # apply all restrictions

use IO::File;

# import all the GSC and database stuff
use GSCApp;

# set up App information
App->pkg_name('pw-cleanup');
App->title('Clean up passwd and shadow file');
App->version('0.1');
App->author('David Dooling');
App->author_email('ddooling@watson.wustl.edu');
App->synopsis(lc(App->title));
App->usage_head('[OPTIONS]... [PASSWD [SHADOW]]');

# process command line options
App->get_options();

# get input files
my ($passwd, $shadow);
$passwd = shift(@ARGV) if @ARGV;
$shadow = shift(@ARGV) if @ARGV;
$passwd ||= '/etc/passwd';
$shadow ||= '/etc/shadow';

# output files
my $passwd_out = "$passwd.clean";
my $shadow_out = "$shadow.clean";
my $passwd_no = "$passwd.inactive";
my $shadow_no = "$shadow.inactive";

# open log file
my $log = App->pkg_name . ".log";
my $log_fh = IO::File->new(">$log");
die(App->pkg_name . ":could not open $log for writing:$!")
    unless defined($log_fh);

# open input and output files
my $pin_fh = IO::File->new("<$passwd");
die(App->pkg_name . ":could not open $passwd for reading:$!")
    unless defined($pin_fh);

# read in all the passwd entries
my %passwd;
while (defined(my $pwent = $pin_fh->getline)) {
    chomp($pwent);
    warn("read passwd line:$pwent") if App::Debug->level > 1;

    # make sure it is an entry
    if ($pwent =~ m/:.*:.*:.*:.*:.*:/) {
        warn("passwd entry $pwent is valid") if App::Debug->level > 1;
    }
    else {
        &log($pin_fh, "passwd entry $pwent is not valid, skipping");
        next;
    }

    # make array into hash
    my %pw;
    @pw{qw(login passwd uid gid name home shell)} = split(m/:/, $pwent);

    my $active = 1;
    # see if entry is commented out
    if ($pwent =~ m/^\#/) {
        warn("passwd entry $pwent is commented out")
            if App::Debug->level > 1;
        # remove comment
        $pw{login} =~ s/^\#\s*//;
        $active = 0;
    }
    elsif ($pw{shell} =~ m/_d$/) { # see if shell is inactive
        $pw{shell} =~ s/_d$//;
        $active = 0;
    }
    elsif ($pw{shell} =~ m/false/) {
        $active = 0;
        # might be a system account
        foreach my $sys (qw( root nobody daemon sys bin adm uucp new ingres 
                             audit lp ))
        {
            if ($pw{login} eq $sys) {
                $active = 1;
                last;
            }
        }
    }
    elsif ($pw{shell} =~ m/date/) {
        $active = 0;
    }

    # make sure passwd is an x
    if ($pw{passwd} eq 'x') {
        warn("passwd entry $pwent password points to shadow")
            if App::Debug->level > 1;
    }
    else {
        &log($pin_fh, "passwd entry $pwent password does not use shadow");
    }

    # put entry back together
    $pwent = join(':', @pw{qw(login passwd uid gid name home shell)});

    # move nobody up in the list
    if ($pw{login} eq 'nobody') {
        $pw{uid} = 0.5;
    }

    # check for duplicates
    if (exists($passwd{$pw{uid}})) {
        # see if both are active
        if ($active && $passwd{$pw{uid}}->{active}) {
            &log($pin_fh, "passwd entry $pwent has duplicate uid");
            next;
        }
        elsif ($passwd{$pw{uid}}->{active}) {
            # keep the active one
            next;
        }
        else {
            # remove the previous inactive one
            delete($passwd{$pw{uid}});
        }
    }

    # put entry into hash, uid is key
    $passwd{$pw{uid}} = {
        login => $pw{login},
        entry => $pwent,
        active => $active
    };
}
$pin_fh->close;

# open shadow file
my $sin_fh = IO::File->new("<$shadow");
die(App->pkg_name . ":could not open $shadow for reading:$!")
    unless defined($sin_fh);

# read in all the shadow entries
my %shadow;
while (defined(my $shent = $sin_fh->getline)) {
    chomp($shent);
    warn("read shadow entry:$shent") if App::Debug->level > 1;

    # make sure it is an entry
    if ($shent =~ m/:.*:.*:.*:.*:.*:.*:.*:/) {
        warn("shadow entry $shent is valid") if App::Debug->level > 1;
    }
    else {
        &log($sin_fh, "shadow entry $shent is not valid, skipping");
        next;
    }

    my $active = 1;
    # see if shadow entry is commented
    if ($shent =~ m/^\#/) {
        warn("shadow entry $shent is commented out")
            if App::Debug->level > 1;
        $shent =~ s/^\#\s*//;
        $active = 0;
    }
    # do not test for * in passwd field as active systems accounts have this

    # get login
    my ($login) = split(m/:/, $shent);

    # check for duplicates
    if (exists($shadow{$login})) {
        # warn if both are active
        if ($active && $shadow{$login}->{active}) {
            &log($sin_fh, "user $login has multiple shadow entries");
            next;
        }
        elsif ($shadow{$login}->{active}) {
            # keep active one
            next;
        }
        else {
            # remove the previous inactive one
            delete($shadow{$login});
        }
    }

    # put in hash
    $shadow{$login} = {
        entry => $shent,
        active => $active
    };
}
$sin_fh->close;

# open output files
my $pout_fh = IO::File->new(">$passwd_out");
die(App->pkg_name . ":could not open $passwd_out for writing:$!")
    unless defined($pout_fh);
my $sout_fh = IO::File->new(">$shadow_out");
die(App->pkg_name . ":could not open $shadow_out for writing:$!")
    unless defined($sout_fh);
my $pno_fh = IO::File->new(">$passwd_no");
die(App->pkg_name . ":could not open $passwd_no for writing:$!")
    unless defined($pno_fh);
my $sno_fh = IO::File->new(">$shadow_no");
die(App->pkg_name . ":could not open $shadow_no for writing:$!")
    unless defined($sno_fh);

# loop through the passwd entries
foreach my $pw (sort({ $a <=> $b } keys(%passwd))) {
    my $login = $passwd{$pw}->{login};

    # make sure it has a corresponding shadow entry
    if (exists($shadow{$login})) {
        warn("passwd entry $login has matching shadow entry")
            if App::Debug->level > 1;
    }
    else {
        # make one
        $shadow{$login} = {
            entry => "$login:*:::::::",
            active => 1
        };
        # warn if account is active
        &log(undef, "passwd entry $login has no matching shadow entry")
             if $passwd{$pw}->{active};
    }

    # see if it is active
    if ($passwd{$pw}->{active}) {
        # make sure shadow is active
        if ($shadow{$login}->{active}) {
            warn("passwd and shadow entry for $login are active")
                if App::Debug->level > 1;
        }
        else {
            &log(undef, "passwd entry for $login is active but shadow is "
                 . "inactive, skipping");
            next;
        }

        # write it out
        $pout_fh->print($passwd{$pw}->{entry}, "\n");
        $sout_fh->print($shadow{$login}->{entry}, "\n");
    }
    else {                      # not active
        $pno_fh->print($passwd{$pw}->{entry}, "\n");
        $sno_fh->print($shadow{$login}->{entry}, "\n");
    }
}

# close file handles
$pout_fh->close;
$sout_fh->close;
$pno_fh->close;
$sno_fh->close;
$log_fh->close;

# restrict access to shadow files
if (chmod(0400, $shadow_out, $shadow_no) == 2) {
    warn("set mode on $shadow_out and $shadow_no") if App::Debug->level;
}
else {
    warn("failed to set mode on $shadow_out and $shadow_no:$!");
    exit(1);
}

# terminate program
exit(0);

# log and print out error
sub log
{
    my ($fh, $msg) = @_;
    $msg = $fh->input_line_number . ":$msg" if $fh;
    warn($msg);
    return $log_fh->print("$msg\n");
}

=pod

=head1 NAME

pw-cleanup - clean up passwd and shadow files.

=head1 SYNOPSIS

B<pw-cleanup> [OPTIONS]... [PASSWD [SHADOW]]

=head1 DESCRIPTION

This script goes through a passwd and shadow file and removes a
comments, makes sure they are in sync, and fixes commented users.

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
