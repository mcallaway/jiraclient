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
    defaultNewUserPassword => "genetics1!",
    ldap_host => 'ldap.dsg.wustl.edu',
    ldap_baseDN => 'uid='.$user.',ou=People,dc=gsc,dc=wustl,dc=edu',
    ad_host => 'dvm1.gsc.wustl.edu',
    ad_username => 'svc_ldap',
    ad_userDN => 'svc_ldap@gc.local',
    ad_password => 'LKy6#!4sW',
    ad_baseDN => "DC=gc,DC=local",
    ad_container => 'DSG_Users',
  };
  bless $self,$class;
  return $self;
}

sub find_ldap_user {
  my $self = shift;
  my $user = shift;

  my $ldaphost = $self->{ldap_host};
  my $LDAPbaseDN = $self->{ldap_baseDN};

  my $ldap = new Net::LDAP( $ldaphost, debug => $self->{debug}) or die "Failed to connect() to $ldaphost: $!";
  my $result;

  $result = $ldap->bind() or die "Failed to bind() to $ldaphost: $!";
  $result = $ldap->start_tls() or die "Failed to start_tls(): $!";

  my $query = '(&(uid='.$user.'))';
  $result = $ldap->search(base => $LDAPbaseDN, filter => $query);
  my $ldapentry  = pop @{ [ $result->entries() ] };
  die "User $user not found in LDAP"
    if (! defined $ldapentry or ! defined $ldapentry->get_value("uid"));
  return $ldapentry;
}

sub ad_connect {
  my $self = shift;

  my $ad_host = $self->{ad_host};
  my $ad_username = $self->{ad_username};
  my $ad_userDN = $self->{ad_userDN};
  my $ad_password = $self->{ad_password};

  my $adldap = new Net::LDAP( $ad_host, debug => $self->{debug}) or die "$@";
  $adldap->bind($ad_userDN,password => $ad_password) or die "Failed to bind() to $ad_host: $!";
  $adldap->start_tls(sslversion => 'sslv3') or die "Failed to start_tls(): $!";
  $self->{adldap} = $adldap;
}

sub user_in_ad {
  my $self = shift;
  my $ldapentry = shift;
  my $user = $ldapentry->get_value("uid");
  my $query = "(&(uid=".$user."))";
  my $ad_baseDN = $self->{ad_baseDN};

  my $result = $self->{adldap}->search(base => $ad_baseDN, filter => $query, attrs => ["samaccountname","mail","memberof","department","displayname","telephonenumber","primarygroupid","objectsid"]);
  my $adentry  = pop @{ [ $result->entries() ] };

  if ( $adentry->get_value("samaccountname") ) {
    # already exists in AD
    print "User $user already exists in AD\n";
    exit;
  }
}

sub ad_adduser {
  my $self = shift;
  my $ldapentry = shift;
  my $user = $ldapentry->get_value("uid");
  my $ad_container = $self->{ad_container};
  my $default_pw = $self->{defaultNewUserPassword},

  my $arg = {
      "cn=$ldapentry->{givenName} $ldapentry->{sn}",
      attr => [
      "username"=>$user,
      "logon_name"=>$user,
      "firstname"=>$ldapentry->{givenName},
      "surname"=>$ldapentry->{sn},
      "email"=>$ldapentry->{mail},
      "container"=>array($ad_container),
      "change_password"=>0,
      "enabled"=>1,
      "password"=>$default_pw,
      ]
  };
  print Dumper($arg);
  return if ($self->{test});
  $self->{adldap}->add( $arg ) or die "Failed to add user $user to AD: $!";
}

sub run {
  my $self = shift;
  my $user = shift;

  die "please specify login id"
    if (! defined $user);

  my $ldapentry = $self->find_ldap_user($user);
  $self->ad_connect();
  $self->user_in_ad($ldapentry);
  $self->ad_adduser($ldapentry);
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

gscuserADadd - Add a user to Active Directory based on what exists in LDAP

=head1 SYNOPSIS

gscuserADadd [options] username

=head1 OPTIONS

 -d N       Enable LDAP debuging [1,2,4,8]
 -h         This helpful message
 -t         Test mode, do everything up to the add

=head1 DESCRIPTION

This script connects to an LDAP server, gathers user info, and adds that
user info to an Active Directory server.

=cut
