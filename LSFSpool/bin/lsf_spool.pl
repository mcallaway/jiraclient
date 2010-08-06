#!/usr/bin/perl

use LSFSpool;
my $app = LSFSpool->new();
my $rc = $app->main(@ARGV);
exit $rc;

