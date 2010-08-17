#!/usr/bin/perl

package du_total;

use du_lib qw/short commify/;

use strict;
use warnings;
use base qw/CGI::Application/;

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

  $self->{cfg} = {
    db => {
      dsn => 'DBI:SQLite:dbname=du.cache',
      attributes => {
        RaiseError => 1,
      },
    }
  };

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
  my $db = $self->{cfg}->{db} or die('Missing config param: db');
  $self->dbh_config($db->{dsn}, '', '', $db->{attributes});

} # /cgiapp_init

sub table_data {
  my $self = shift;
  my $q = $self->query();

  my @aaData = $self->_get_table_content();

  # -- reform single row of table data into a hash table
  my $sOutput = {};
  foreach my $item ($aaData[0]) {
    $sOutput = {
      total_kb      => $item->[0],
      used_kb       => $item->[1],
      capacity      => $item->[2],
      last_modified => $item->[3],
    };
  }

  return $self->to_json($sOutput);
} # /table_data

sub _get_table_content {

  my $self = shift;
  my @aaData = ();

  my $dbh = $self->dbh();

  # total and used KB
  my $sql = qq~SELECT SUM(total_kb),SUM(used_kb) FROM disk_df~;
  my $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  my $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  while( my @a = $sth->fetchrow_array() ) {
    # Calculate capacity before formatting numbers into strings
    my $cap = sprintf "%d%%", $a[1]/$a[0] * 100;

    # Format numbers with commas
    $a[0] = du_lib::commify($a[0]) . " (" . du_lib::short($a[0]) . ")";
    $a[1] = du_lib::commify($a[1]) . " (" . du_lib::short($a[1]) . ")";

    # Add capacity
    push @a,$cap;
    push @aaData, @a;
  }

  # Add most recent last_modified
  $sql = qq~SELECT last_modified FROM disk_hosts ORDER BY last_modified DESC LIMIT 1~;
  $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  while( my @a = $sth->fetchrow_array() ) {
    push @aaData, @a;
  }

  $sth->finish(); # clean up

  return \@aaData;
}

1;

use strict;
use warnings;
use FindBin qw/$Bin/;

my $app = du_total->new();
$app->run();

