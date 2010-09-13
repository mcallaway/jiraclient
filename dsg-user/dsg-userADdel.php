#!/usr/bin/env php
<?php

  if (count($argv) == 1) {
    echo "\nThis script is designed to delete users in windows active directory for the gc.local domain";
    echo "\nThis script is only designed to be run as user root on vm28";
    echo "\nThis script should be given a username of an AD user as input\n\n";
    exit(1);
  }
  else {
    $user = $argv[1];
  }

  include ("/dsg/share/scripts/DSG_adLDAP_3.3.1.php");
  $adLDAP=new adLDAP();

  // Look up the specified user in AD
  try {
      $userinfo = $adLDAP->user_info($user,array("samaccountname"));
  }
  catch (adLDAPException $e) {
    echo "Error :".$e; exit(1);   
  }
  
  // If the user was found delete it, other wise exit
  $AdUserName = $userinfo[0][samaccountname][0];
  if ($user != $AdUserName) {
    echo "This user does not exist in the DSG active directory, so I am not deleting it.\n";
  }
  else {
    echo "Deleting $user from DSG active directory...";
    try {
        $result=$adLDAP->user_delete($user);
        //var_dump($result);
    }
    catch (adLDAPException $e) {
        echo "Error :".$e; exit(1);
    }
    if ($result != true) {
       echo "Deleting user from AD failed\n";
       exit(1);
    }
    else {
        echo "complete.\n";
    }
  }
exit(0);

?> 

