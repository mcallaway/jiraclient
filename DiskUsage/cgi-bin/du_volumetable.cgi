#!/usr/bin/perl

package DataTableServer;

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

  # -- Define the name of the table that holds the data.
  my $table = 'disk_df';

  # -- Select
  my $select = "SELECT mount_path, physical_path, total_kb, used_kb, ROUND((CAST(used_kb AS REAL)/total_kb * 100),2) as capacity, group_name, last_modified FROM $table";

  # -- Filtering: applies DataTables search box
  my $where = $self->_generate_where_clause();
  if ($where) {
    $select .= $where;
  }

  # -- Ordering: makes DataTables column sorting work
  my $order = $self->_generate_order_clause();
  if ($order) {
    $select .= $order;
  }

  # -- Paging
  my $limit = $q->param('iDisplayLength') || 10;
  my $offset = 0;
  if( $q->param('iDisplayStart') ) {
    $offset = $q->param('iDisplayStart');
  }
  if ($limit) {
    $select .= " LIMIT $limit";
  }

  # -- get table contents
  my @aaData = $self->_get_table_content( $table, $select );

  # -- get meta information about the resultset
  my $iFilteredTotal = scalar @aaData;
  my $iTotal = $self->_get_total_record_count( $table );

  # -- build final data structure
  my $sEcho = defined $q->param('sEcho') ? $q->param('sEcho') : 1;
  my $sOutput = {
    sEcho => $sEcho,
    iTotalRecords => int($iTotal),
    iTotalDisplayRecords => int($iFilteredTotal),
    aaData => \@aaData,
  };

  return $self->to_json($sOutput);
} # /table_data

sub _generate_order_clause {
  my $self = shift;
  my $q = $self->query();

  my @order = ();
  if( defined $q->param('iSortCol_0') ){
    for( my $i = 0; $i < $q->param('iSortingCols'); $i++ ) {
      # We only get the column index (starting from 0), so we have to
      # translate the index into a column name.
      my $column_name = $self->_fnColumnToField( $q->param('iSortCol_'.$i) );
      my $direction = $q->param('sSortDir_'.$i);
      push @order, "$column_name $direction";
    }
  }

  my $order;
  $order .= " ORDER BY " . join(',',@order) if (@order);
  return $order;
} # /_generate_order_clause

sub _generate_where_clause {
  my $self = shift;
  my $q = $self->query();

  my @where;

  if( defined $q->param('sSearch') ) {
    my $search_string = $q->param('sSearch');
    for( my $i = 0; $i < $q->param('iColumns'); $i++ ) {
      # Iterate over each column and check if it is searchable.
      # If so, add a constraint to the where clause restricting the given
      # column. In the query, the column is identified by it's index, we
      # need to translates the index to the column name.
      my $searchable_ident = 'bSearchable_'.$i;
      if( $q->param($searchable_ident) and $q->param($searchable_ident) eq 'true' ) {
        my $column = $self->_fnColumnToField( $i );
        push @where,"$column LIKE \"%%$search_string%%\"";
      }
    }
  }

  my $where;
  $where .= " WHERE " . join(" OR ",@where) if (@where);
  return $where;
} # /_generate_where_clause

sub _fnColumnToField {
  my $self = shift;
  my $i = shift;

  # Note: we could have used an array, but for dispatching purposes, this is
  # more readable.
  my %dispatcher = (
    # column => 'rowname',
    0 => 'mount_path',
    1 => 'physical_path',
    2 => 'total_kb',
    3 => 'used_kb',
    4 => 'capacity',
    5 => 'group_name',
    6 => 'last_modified',
  );

  die("No such row index defined: $i") unless exists $dispatcher{$i};

  return $dispatcher{$i};
} # /_fnColumnToField

sub _get_table_content {

  my $self = shift;
  my $table = shift or die("Missing table.");
  my $sql = shift or die("Missing sql.");

  my $q = $self->query();
  my $dbh = $self->dbh();

  my $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  my $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");

  my @aaData = ();
  while( my @a = $sth->fetchrow_array() ) {
    # A hack to fix double // in returned mount point
    $a[0] =~ s/\/\//\//;
    $a[2] = $self->_commify($a[2]) . " (" . $self->_short($a[2]) . ")";
    $a[3] = $self->_commify($a[3]) . " (" . $self->_short($a[3]) . ")";
    # A hack to work around an empty capacity column
    $a[4] = 0 if (!defined $a[4]);
    # Don't add % or javascript can't do numeric tests
    #$a[4] = "$a[4]%";
    push @aaData, \@a;
  }
  $sth->finish(); # clean up

  return @aaData;
} # /_get_table_content

sub _get_total_record_count {

  my $self = shift;
  my $table = shift or die("Missing table name.");

  my $dbh = $self->dbh();
  my $sql = qq~SELECT COUNT(df_id) AS count FROM $table~;
  my $sth = $dbh->prepare($sql) or die("Error preparing sql: " . DBI->errstr() . "\nSQL: $sql\n");
  my $rv = $sth->execute() or die("Error executing sql: " . DBI->errstr() . "\nSQL: $sql\n");

  my $cnt = -1;
  while( my $href = $sth->fetchrow_hashref() ) {
    $cnt = $href->{count};
  }

  return $cnt;
} # /_get_total_record_count

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
  my $number = shift;
  # commify a number. Perl Cookbook, 2.17, p. 64
  my $text = reverse $number;
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
}


1;

use strict;
use warnings;
use FindBin qw/$Bin/;

my $app = DataTableServer->new(
  PARAMS => {
      cfg_file => $Bin . '/du.config',
  },
);
$app->run();

