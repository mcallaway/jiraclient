#!/usr/bin/env php
<?php

  if (count($argv) == 1) {
    echo "\nThis script is designed to create new user in windows active directory for the gc.local domain";
    echo "\nGiven a user name this script will look up details in OpenLDAP and then use that info";
    echo "\nto create an AD account.  As part of the user provisioning process this is executed automaticially";
    echo "\nafter the user has been added to LDAP";
    echo "\nThis script is only designed to be run as user root on vm28";
    echo "\nThis script should be given a username of an LDAP user as input\n\n";
    exit(1);
  }
  else {
    $user = $argv[1];
  }

  include ("/root/scripts/GC_adLDAP_3.3.1.php");
  $adLDAP=new adLDAP();

  $defaultNewUserPassword="genomes1!";

  // configuration values
  $ldapHost = 'ldapmaster.gsc.wustl.edu';
  $userDn = 'uid='.$user.',ou=People,dc=gsc,dc=wustl,dc=edu';

  // connect to ldap server
  $ldapConn = ldap_connect($ldapHost)
    or die("Could not connect to LDAP server\n");
  // set protocol version 3
  ldap_set_option($ldapConn, LDAP_OPT_PROTOCOL_VERSION, 3)
    or die("Was not able to set LDAP protocol version to 3\n");
  // establish TLS connection
  if (!ldap_start_tls($ldapConn))
    die("Was not able to start encrypted session with LDAP server\n");
  echo "\nLDAP connect successful...\n\n";

  // anonymous bind to ldap
  $ldapBind=ldap_bind($ldapConn)
    or die("Was not able to make an anonymous bind to ldap\n");

  $query = "(&(uid=".$user."))";
  $search_result = ldap_search($ldapConn, "ou=People,dc=gsc,dc=wustl,dc=edu", $query);
  $entry = ldap_first_entry($ldapConn, $search_result);
  if ($entry == false) {
    echo "\nUser $user was not found in LDAP, so I am not adding to AD\n\n";
    exit(1);
  }

  //look up email address
  $values = ldap_get_values($ldapConn, $entry, "mail");
  $email = $values[0];
  //echo "Email: $email\n";

  //look up last name
  $values = ldap_get_values($ldapConn, $entry, "sn");
  $userLastName = $values[0];
  //echo "last name: $userLastName\n";

  //look up first name
  $values = ldap_get_values($ldapConn, $entry, "givenName");
  $userFirstName = $values[0];
  //echo "first name: $userFirstName\n";

// Enter the information we gathered from LDAP into AD
  try {
      $userinfo = $adLDAP->user_info($user,array("samaccountname"));
  }
  catch (adLDAPException $e) {
    echo "Error :".$e; exit(1);   
  }
  $AdUserName = $userinfo[0][samaccountname][0];
  if ($user == $AdUserName) {
    echo "This user already exists in the GC active directory, so I am not creating it.\n";
  }
  else {
    echo "Adding $user to GC active directory...";
    $attributes=array(
                "username"=>$user,
                "logon_name"=>$user,
                "firstname"=>$userFirstName,
                "surname"=>$userLastName,
                "email"=>$email,
                "container"=>array('GC_Users'),
                "change_password"=>0,
                "enabled"=>1,
                "password"=>$defaultNewUserPassword,
    );
    try {
        $result=$adLDAP->user_create($attributes);
        //var_dump($result);
    }
    catch (adLDAPException $e) {
        echo "Error :".$e; exit(1);
    }
    if ($result != true) {
       echo "Adding user to AD failed\n";
       exit(1);
    }
    else {
        echo "complete.\n";
    }
  }
exit(0);

?> 
