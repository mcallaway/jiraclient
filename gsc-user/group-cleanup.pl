#! /gsc/bin/perl
# Clean up group file.
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

use IO::File;

# import all the GSC and database stuff
use GSCApp;

# set up App information
App->pkg_name('group-cleanup');
App->title('Clean up group file');
App->version('0.1');
App->author('David Dooling');
App->author_email('ddooling@watson.wustl.edu');
App->synopsis(lc(App->title));
App->usage_head('[OPTIONS]... [GROUP]');

# process command line options
App->get_options();

# get input files
my ($group);
$group = shift(@ARGV) if @ARGV;
$group ||= '/etc/group';

# output file
my $group_out = "$group.clean";

# open log file
my $log = App->pkg_name . ".log";
my $log_fh = IO::File->new(">$log");
die(App->pkg_name . ":could not open $log for writing:$!")
    unless defined($log_fh);

# open input and output files
my $gin_fh = IO::File->new("<$group");
die(App->pkg_name . ":could not open $group for reading:$!")
    unless defined($gin_fh);

# read in all the passwd entries
my (%group, %gid);
while (defined(my $gent = $gin_fh->getline)) {
    chomp($gent);
    warn("read passwd line:$gent") if App::Debug->level > 1;

    # make sure it is an entry
    if ($gent =~ m/::.*:/) {
        warn("group entry $gent is valid") if App::Debug->level > 1;
    }
    else {
        &log($gin_fh, "group entry $gent is not valid, skipping");
        next;
    }

    # check for white space
    if ($gent =~ m/\s/) {
        &log($gin_fh, "group entry $gent has white space, not valid, skipping");
        next;
    }        

    # make array into hash
    my %gr;
    @gr{qw(group passwd gid logins)} = split(m/:/, $gent);

    # make sure passwd is empty
    if ($gr{passwd}) {
        &log($gin_fh, "group passwd entry $gent is not empty");
        $gr{passwd} = '';
    }

    # check members
    if ($gr{logins}) {
        my @logins = split(m/,/, $gr{logins});
        $gr{logins} = '';
        foreach my $login (@logins) {
            if (defined(getpwnam($login))) {
                warn("group $gent member $login exists")
                    if App::Debug->level > 2;
                $gr{logins} .= "$login,";
            }
            else {
                &log($gin_fh, "group $gr{group} has nonexistant member:$login");
            }
        }
        # remove last comma
        chop($gr{logins});
    }
    else {
        $gr{logins} = '';
    }

    # put entry back together
    $gent = join(':', @gr{qw(group passwd gid logins)});

    # check for duplicates
    if (exists($group{$gr{group}})) {
        &log($gin_fh, "group entry $gent has duplicate group name");
        next;
    }
    if (exists($gid{$gr{gid}})) {
        &log($gin_fh, "group entry $gent has duplicate gid");
        next;
    }

    # move no* groups up in the list
    if ($gr{group} =~ m/^no/) {
        $gr{gid} = "15.$gr{gid}";
    }
    
    # put entry into hash, uid is key
    $gid{$gr{gid}} = $gent;
    $group{$gr{group}} = 1;
}
$gin_fh->close;

# open output files
my $gout_fh = IO::File->new(">$group_out");
die(App->pkg_name . ":could not open $group_out for writing:$!")
    unless defined($gout_fh);

# loop through the group entries
foreach my $gr (sort({ $a <=> $b } keys(%gid))) {
    $gout_fh->print("$gid{$gr}\n");
}

# close file handles
$gout_fh->close;

# terminate program
exit(0);

# log and print out error
sub log
{
    my ($fh, $msg) = @_;
    $msg = $fh->input_line_number . ":$msg" if $fh;
    #warn($msg);
    return $log_fh->print("$msg\n");
}

=pod

=head1 NAME

group-cleanup - clean up group files.

=head1 SYNOPSIS

B<group-cleanup> [OPTIONS]... [GROUP]

=head1 DESCRIPTION

This script goes through a group file and makes sure all the entries
are valid.
users.

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
