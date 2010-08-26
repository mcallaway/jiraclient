#!/usr/bin/perl

package du_lib;

our $VERSION = "0.9.0";

sub short {
  my $number = shift;

  my $cn = commify($number);
  my $size = 0;
  $size++ while $cn =~ /,/g;

  my $units = {
    0 => 'KB',
    1 => 'MB',
    2 => 'GB',
    3 => 'TB',
    4 => 'PB',
  };
  my $round = {
    0 => 1,
    1 => 1000,
    2 => 1000000,
    3 => 1000000000,
    4 => 1000000000000,
  };
  my $n = int($number / $round->{$size} + 0.5);
  return "$n " . $units->{$size};
}

sub commify {
  my $number = shift;
  # commify a number. Perl Cookbook, 2.17, p. 64
  my $text = reverse $number;
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
}

1;
