#!/usr/bin/env perl

use DiskUsage;

my $app = DiskUsage->new();
my $rc = $app->main(@ARGV);
exit $rc;
