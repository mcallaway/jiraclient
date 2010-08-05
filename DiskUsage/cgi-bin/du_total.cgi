#!/usr/bin/perl

BEGIN {
  push @INC, '/Users/mcallawa/perl5/lib/perl5';
}

package Top;

use strict;
use warnings;
use base qw/CGI::Application/;

use CGI::Application::Plugin::ConfigAuto (qw/cfg/);
use CGI::Application::Plugin::JSON 'to_json';
use CGI::Application::Plugin::DBH (qw/dbh_config dbh/);

use Data::Dumper qw/Dumper/;

our $VERSION = 0.2;

sub setup {
  my $self = shift;

  $self->start_mode('table_data');
  $self->run_modes([qw/table_data/]);

} # /setup

sub cgiapp_init {
  my $self = shift;

  # Set some defaults for DFV unless they already exist...
  $self->param('dfv_defaults') ||
        $self->param('dfv_defaults', {
                missing_optional_valid => 1,
                filters => 'trim',
                msgs => {
                    any_errors => 'some_errors',
                    prefix     => 'err_',
                    invalid    => 'Invalid',
                    missing    => 'Missing',
                    format => '<span class="dfv-errors">%s</span>',
                },
        });

  # -- set up database
  my $db = $self->cfg('db') or die('Missing config param: db');
  $self->dbh_config($db->{dsn}, '', '', $db->{attributes});

} # /cgiapp_init

sub table_data {
  my $self = shift;
  my $q = $self->query();

  my $table = "disk_df";

  my @aaData = $self->_get_table_content($table);

  # -- reform single row of table data into a hash table
  my $sOutput = {};
  foreach my $item ($aaData[0]) {
    $sOutput = {
      total_kb => $item->[0],
      used_kb  => $item->[1],
      capacity => $item->[2],
    };
  }

  return $self->to_json($sOutput);
} # /table_data

sub _get_table_content {

  my $self = shift;
  my $table = shift or die("Missing table name.");

  my $dbh = $self->dbh();
  my $sql = qq~SELECT SUM(total_kb),SUM(used_kb) FROM $table~;
  my $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  my $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");

  my @aaData = ();
  while( my @a = $sth->fetchrow_array() ) {
    # Calculate capacity before formatting numbers into strings
    my $cap = sprintf "%d%%", $a[1]/$a[0] * 100;

    # Format numbers with commas
    $a[0] = $self->_commify($a[0]) . " (" . $self->_short($a[0]) . ")";
    $a[1] = $self->_commify($a[1]) . " (" . $self->_short($a[1]) . ")";

    # Add capacity
    push @a,$cap;
    push @aaData, \@a;
  }
  $sth->finish(); # clean up

  return @aaData;
}

sub _short {
  my $self = shift;
  my $number = shift;

  my $cn = $self->_commify($number);
  my $size = 0;
  $size++ while $cn =~ /,/g;

  my $units = {
    0 => 'KB',
    1 => 'MB',
    2 => 'GB',
    3 => 'TB',
    4 => 'PB',
    5 => 'EB',
  };
  my $round = {
    0 => 1,
    1 => 1000,
    2 => 1000000,
    3 => 1000000000,
    4 => 1000000000000,
    5 => 1000000000000000,
  };
  my $n = int($number / $round->{$size} + 0.5);
  return "$n " . $units->{$size};
}

sub _commify {
  my $self = shift;
  # commify a number. Perl Cookbook, 2.17, p. 64
  my $text = reverse $_[0];
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
  return $text
}


1;

use strict;
use warnings;
use FindBin qw/$Bin/;

my $app = Top->new(
  PARAMS => {
      cfg_file => $Bin . '/du.config',
  },
);
$app->run();

