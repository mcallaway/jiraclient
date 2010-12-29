#!/usr/bin/env perl

package dsguserAD;

use strict;
use warnings;

use Net::LDAP;
use Data::Dumper qw/Dumper/;
use Term::ReadKey;
use utf8;

# Convenience function to test utf8 encoding
sub _is_encoded {
  my $str = shift;
  if ( $str =~ m/^"\000.+"\000$/ ) {
      return 1;
  }
  return 0;
}

# Convenience function to encode in utf8
sub _encode {
  my $line = shift;

  return $line if ( _is_encoded($line) );

  my $nline = '';
  map { $nline .= "$_\000" } split( //, "\"$line\"" );
  return $nline;
}

sub new {
  my $class = shift;
  my $debug = shift;
  # This debug is Net::LDAP debugging turned all the way up.
  $debug = 8 if ($debug);
  my $self = {
    test => shift,
    adldap => undef,
    debug => $debug,
    defaultNewUserPassword => "genetics1!",
    ldap_host => 'ldap.dsg.wustl.edu',
    ldap_baseDN => 'ou=People,dc=dsg,dc=wustl,dc=edu',
    ad_principal => 'dsg.local',
    ad_host => 'dvm1.dsg.wustl.edu',
    ad_username => 'dsgad',
    ad_userDN => 'dsgad@dsg.local',
    ad_baseDN => "DC=dsg,DC=local",
    ad_container => 'OU=Genetics',
  };
  bless $self,$class;
  return $self;
}

sub find_ldap_user {
  my $self = shift;
  my $user = shift;

  my $ldaphost = $self->{ldap_host};
  my $ldap_baseDN = "uid=$user,$self->{ldap_baseDN}";
  my $ldap = new Net::LDAP( $ldaphost, debug => $self->{debug}) or die "Failed to connect() to $ldaphost: $!";

  my $result;
  $result = $ldap->start_tls() or die "Failed to start_tls(): $!";
  $result = $ldap->bind() or die "Failed to bind() to $ldaphost: $!";
  die "error when binding: ", $result->error()
    if ($result->is_error());

  my $query = '(&(uid='.$user.'))';
  $result = $ldap->search(base => $ldap_baseDN, filter => $query);
  
  my $ldapentry  = pop @{ [ $result->entries() ] };
  die "User $user not found in LDAP"
    if (! defined $ldapentry or ! defined $ldapentry->get_value("uid"));
  $self->{ldapentry} = $ldapentry;
  $ldap->unbind();
}

sub ad_connect {
  my $self = shift;
  my $ad_host = $self->{ad_host};
  my $ad_username = $self->{ad_username};
  my $ad_userDN = $self->{ad_userDN};

  # prompt for AD password
  ReadMode 'noecho';
  print "Enter AD admin password: ";
  my $secret = ReadLine(0);
  ReadMode 'normal';
  chomp $secret;
  print "\n";

  my $adldap = new Net::LDAP( $ad_host, debug => $self->{debug}) or die "$@";
  $adldap->start_tls(sslversion => 'sslv3') or die "Failed to start_tls(): $!";
  my $result = $adldap->bind($ad_userDN,password => $secret) or die "Failed to bind() to $ad_host: $!";
  die "error when binding: ", $result->error()
    if ($result->is_error());
  $self->{adldap} = $adldap;
}

sub user_in_ad {
  my $self = shift;
  my $user = shift;

  my $ad_baseDN = $self->{ad_baseDN};
  my $query = "sAMAccountName=$user";
  my $result = $self->{adldap}->search(base => $ad_baseDN, filter => $query );

  die "Fatal Error: AD has more than one user with $query\n"
    if ( $result->count > 1 );
  $self->{adentry}  = pop @{ [ $result->entries() ] };
}

sub ad_adduser {
  my $self = shift;
  my $user = shift;

  my $default_pw = $self->{defaultNewUserPassword};
  my $ad_container = $self->{ad_container};
  my $base_dn = $self->{ad_baseDN};

  # user must exist in ldap before we add to AD
  $self->find_ldap_user($user);

  my $ldapentry = $self->{ldapentry};
  my $cn = $ldapentry->get_value('cn');
  my $dn = "CN=$cn,$ad_container,$base_dn";

  $default_pw = _encode($default_pw);

  $self->ad_connect();
  $self->user_in_ad($user);

  my $attr = [
      "sAMAccountName" => $user,
      "objectclass"    => [ "top", "person", "organizationalPerson", "user" ],
      "cn"             => $cn,
      "name"           => $cn,
      "displayname"    => $cn,
      "givenName"      => $ldapentry->get_value('givenName'),
      "userprincipalname" => "$user\@$self->{ad_principal}",
      "sn"             => $ldapentry->get_value('sn'),
      "pwdLastSet"     => 0,
      "unicodePwd"     => $default_pw,
  ];

  if ($self->{test}) {
    print "Would add: $dn\n";
    print Dumper($attr);
    return;
  }

  die "User $user already exists in AD\n"
    if ( defined $self->{adentry} and
         $self->{adentry}->get_value("samaccountname") );

  my $result = $self->{adldap}->add( dn => $dn, attr => [ @$attr ] );
  if ($result->code) {
    print "Error adding DN: $dn\n";
    print $result->error_name . "\n";
    print $result->error_text . "\n";
    print $result->mesg_id . "\n";
    print $result->dn . "\n";
  } else {
    print "Successfully added DN: $dn\n";
  }
  $self->{adldap}->unbind();
}

sub ad_deluser {
  my $self = shift;
  my $user = shift;

  $self->ad_connect();
  $self->user_in_ad($user);

  die "User $user does not exist in AD\n"
    if ( ! defined $self->{adentry} or
         ! $self->{adentry}->get_value("samaccountname") );

  my $dn = $self->{adentry}->{asn}->{objectName};

  if ($self->{test}) {
    print "Would remove: $dn\n";
    return;
  }
  my $result = $self->{adldap}->delete( $dn ) or die "Failed to remove user from AD: $!";
  if ($result->code) {
    print "Error removing DN: $dn\n";
    print $result->error_name . "\n";
    print $result->error_text . "\n";
    print $result->mesg_id . "\n";
    print $result->dn . "\n";
  } else {
    print "Successfully removed DN: $dn\n";
  }
  $self->{adldap}->unbind();
}

package main;

use Getopt::Std;
use Pod::Find qw(pod_where);
use Pod::Usage;

my %opts;
getopts("adhtv",\%opts) or die "error parsing args";
my $debug = delete $opts{v} ? 1 : 0;
my $test  = delete $opts{t} ? 1 : 0;
my $add   = delete $opts{a} ? 1 : 0;
my $del   = delete $opts{d} ? 1 : 0;

if (delete $opts{h}) {
  pod2usage( -verbose =>1, -input => pod_where({-inc => 1}, __PACKAGE__) );
  exit 0;
}

if ( ( $add and $del ) or ( ! $add and ! $del ) ) {
  die "choose exactly one of either -a or -d";
}

my $user = $ARGV[0];
die "please specify login id" if (! defined $user);

my $app = dsguserAD->new($debug,$test);
$app->ad_adduser($user) if ($add);
$app->ad_deluser($user) if ($del);

__END__

=pod

=head1 NAME

dsguserAD - Add a user to Active Directory based on what exists in LDAP

=head1 SYNOPSIS

dsguserAD [options] username

=head1 OPTIONS

 -a         Add user
 -d         Add user
 -h         This helpful message
 -t         Test mode, do everything up to the add
 -v         Enable verbose LDAP debugging

=head1 DESCRIPTION

This script connects to an LDAP server, gathers user info, and adds that
user info to an Active Directory server.

=cut

