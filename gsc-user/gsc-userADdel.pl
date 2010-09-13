#!/usr/bin/env perl

package gscuserADadd;

use strict;
use warnings;

use Net::LDAP;
use Data::Dumper qw/Dumper/;

sub new {
  my $class = shift;
  my $self = {
    debug => shift,
    test => shift,
    adldap => undef,
  };
  bless $self,$class;
  return $self;
}

sub ad_connect {
  my $self = shift;
  my $adhost = 'vm37.gsc.wustl.edu';
  my $ad_username='svc_ldap';
  my $ad_userDN='svc_ldap@gc.local';
  my $ad_password='LKy6#!4sW';
  my $adldap = new Net::LDAP( $adhost, debug => $self->{debug}) or die "$@";
  $adldap->bind($ad_userDN,password => $ad_password) or die "Failed to bind() to $adhost: $!";
  $adldap->start_tls(sslversion => 'sslv3') or die "Failed to start_tls(): $!";
  $self->{adldap} = $adldap;
}

sub user_in_ad {
  my $self = shift;
  my $user = shift;
  my $ADbaseDN = "DC=gc,DC=local";
  my $query = "(&(uid=".$user."))";
  my $result = $self->{adldap}->search(base => $ADbaseDN, filter => $query, attrs => ["samaccountname","mail","memberof","department","displayname","telephonenumber","primarygroupid","objectsid"]);
  my $adentry  = pop @{ [ $result->entries() ] };
  if (! defined $adentry->get_value("samaccountname") ) {
    print "User $user does not exist in AD\n";
    exit;
  }
  return $adentry;
}

sub ad_deluser {
  my $self = shift;
  my $adentry = shift;
  my $dn = $adentry->{asn}->{objectName};
  if ($self->{test}) {
    print "Would remove: $dn\n";
    return;
  }
  #$self->{adldap}->delete( $dn ) or die "Failed to remove user $user from AD: $!";
}

sub run {
  my $self = shift;
  my $user = shift;

  die "please specify login id"
    if (! defined $user);

  $self->ad_connect();
  my $adentry = $self->user_in_ad($user);
  $self->ad_deluser($adentry);
}

package main;

use Getopt::Std;
use Pod::Find qw(pod_where);
use Pod::Usage;

my %opts;
getopts("d:ht",\%opts) or die "error parsing args";
my $debug = delete $opts{d};
my $test = delete $opts{t} ? 1 : 0;

if (delete $opts{h}) {
  pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
  exit 0;
}

my $user = $ARGV[0];
my $app = gscuserADadd->new($debug,$test);
$app->run($user);

__END__

=pod

=head1 NAME

gscuserADdel - Remove a user from Active Directory.

=head1 SYNOPSIS

gscuserADdel [options] username

=head1 OPTIONS

 -d N       Enable LDAP debuging [1,2,4,8]
 -h         This helpful message
 -t         Test mode, do everything up to the remove

=head1 DESCRIPTION

This script connects to an LDAP server, gathers user info, and adds that
user info to an Active Directory server.

=cut
