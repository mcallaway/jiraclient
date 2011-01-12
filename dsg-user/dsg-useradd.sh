#! /bin/bash
# Create a new user in NIS and LDAP.
# Copyright (C) 2008 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# set up script
pkg=dsg-useradd
version=1.7

login=
email=
forward=
groups=
name=
shell=/bin/bash
test=
uid=
mailaccount=1
# loop through positional parameters
prev_arg=
optarg=
for arg
  do
  if test -n "$prev_arg"; then
      eval "$prev_arg=\$arg"
      prev_arg=
      continue
  fi

  case "$arg" in
      -*=*) optarg=`echo "$arg" | sed 's/[-_a-zA-Z0-9]*=//'` ;;
      *) optarg= ;;
  esac

  case "$arg" in
      -c)
          prev_arg=name
          ;;

      -e | --email | --emai | --ema | --em | --e)
          email=1
          ;;

      -f | --forward | --forwar | --forwa | --forw | --for | --fo | --f)
          prev_arg=forward
          ;;

      --forward=* | --forwar=* | --forwa=* | --forw=* | --for=* | --fo=* | --f=*)
          forward="$optarg"
          ;;

      -G)
          prev_arg=groups
          ;;

      --groups | --group | --grou | --gro | --gr | --g)
          prev_arg=groups
          ;;

      --groups=* | --group=* | --grou=* | --gro=* | --gr=* | --g=*)
          groups="$optarg"
          ;;

      -h | --help | --hel | --he | --h)
      cat <<EOF
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -c                  same as --name
  -e,--email          set up email only account
  -f,--forward=ADDR   forward all email to account to ADDR
  -G,--groups=G1,G2   additional groups to put user into
  -h,--help           print this message and exit
  -n,--name="F L"     specify name of user
  -s,--shell=PATH     set user shell to PATH, default /gsc/bin/bash
  -t,--test           do not actually do anything
  -u,--uid=N          set user uid to N
  --version           print version number and exit
  -z                  no email account for this user


EOF
      exit 0;;

      -n | --name | --nam | --na | --n)
          prev_arg=name
          ;;

      --name=* | --nam=* | --na=* | --n=*)
          name="$optarg"
          ;;

      -s | --shell | --shel | --she | --sh | --s)
          prev_arg=shell
          ;;

      --shell=* | --shel=* | --she=* | --sh=* | --s=*)
          shell="$optarg"
          ;;

      -t | --test | --tes | --te | --t)
          test=1
          ;;

      -u | --uid | --ui | --u)
          prev_arg=uid
          ;;

      --uid=* | --ui=* | --u=*)
          uid="$optarg"
          ;;

      --version | --versio | --versi | --vers | --ver | --ve)
      echo "$pkg $version"
      exit 0
      ;;

      -z)
          mailaccount=0
          ;;

      -*)
      echo "$pkg: unrecognized option: $arg"
      echo "$pkg: Try '$pkg --help' for more information."
      exit 1;;

      *)
          if [ "$login" ]; then
              echo "$pkg: you may create only one user per invokation"
              exit 1
          fi
          login="$arg"
          ;;
  esac
done

# set up our environment
profile=/dsg/share/dsg-login/system.profile
if [ -f "$profile" ]; then
    . $profile
    PATH=/dsg/share/scripts:$PATH
    export PATH
else
    echo "$pkg: system profile does not exist"
    exit 2
fi

# make sure this is being run properly
if [ -z "$test" ]; then
    # check that running as root
    if [ $(id -u) -ne 0 ]; then
        echo "$pkg: you are not root"
        exit 1
    fi
fi
# check that running on goldn1
host=$(hostname | sed 's/\..*//')
if [ $host != goldn1 ]; then
    echo "$pkg: not running on goldn1: $host"
    exit 1
fi

# see if login name was given on command line
if [ -z "$login" ]; then
    echo -n "$pkg: please enter login name: "
    read login
fi
# make sure login is not too long
if [ "${#login}" -gt 8 ]; then
    echo "$pkg: login name $login too long"
    exit 1
fi

# see if login is in use
`ldapsearch -x uid=$login uid | grep -q uid:`
if [ $? -eq 0 ]; then
    echo "$pkg: login $login is already in use"
    exit 1
fi


# get the uid
if [ "$uid" ]; then
    # make sure it is not in use
    `ldapsearch -x uidNumber=$uid uidNumber | grep -q uidNumber:`
    if [ $? -eq 0 ]; then
        echo "$pkg: uid $uid is already in use"
        exit 1
    fi
else
    # get the highest uid in the passwd file
    #maxuid=$(awk -F : '!/^no/{print $3}' $passwd | sort -n -r | head -n 1)
    maxuid=`ldapsearch -x "(uidNumber=*)" uidNumber | grep uidNumber: | awk '{ print $2 }' | sort -n -r | head -n 1`
    if [ -z "$maxuid" ]; then
        echo "$pkg: failed to determine maximum uid"
        exit 2
    fi
    minuid=2000
    if [ $maxuid -lt $minuid ]; then
        uid=$minuid
    else
        uid=$((maxuid + 1))
    fi
    if [ $maxuid -gt 60000 ]; then
        echo "$pkg: error getting maximum uid, it exceeds 60000: $maxuid"
        exit 2
    fi
fi

# get name
if [ -z "$name" ]; then
    echo -n "$pkg: please enter full name of user: "
    read name
fi

# get gid for main group
group=genetics
gid=`ldapsearch -x "(cn=genetics)" gidNumber | grep gidNumber: | awk '{ print $2 }'`
if [ -z "$gid" ]; then
    echo "$pkg: failed to determine gid for group $group"
    exit 2
fi

# allow users to have more groups
if [ "$group" = 'genetics' ]; then
    # get extra groups
    if [ -z "$groups" ]; then
        echo "$pkg: user has primary group $group"
        echo -n "$pkg: please enter comma separated additional groups: "
        read groups
    fi
fi

# set home directory
dir="/dsguser/$login"

# set shell for email accounts
if [ "$email" = 1 ]; then
    shell=/bin/false
fi

# add user to ldap
userldap="dsg-userldap add "
if [ "$test" ]; then
    userldap="echo $pkg: $userldap"
fi
if ! $userldap $login $uid "$name" $shell $gid $groups; then
    echo "$pkg: failed to add user to ldap"
    exit 2
fi


# create users home directory
if [ -z "$email" ]; then
    homedir="/dsg/share/scripts/dsg-homedir --uid=$uid --gid=$gid $login"
    if [ "$test" ]; then
        homedir="echo $pkg: $homedir"
    fi
    if ! $homedir; then
        echo "$pkg: failed to create home directory: $homedir"
        exit 2
    fi
fi

# create mailboxes on imap server
if [ -z "$forward" -a "$mailaccount" -eq 1 ]; then
    # only create space for non-forwarded accounts
    mailimap="ssh -x dsgmail /dsg/share/scripts/dsg-mailimap --uid=$uid --gid=$gid $login"
    if [ "$test" ]; then
        mailimap="echo $pkg: $mailimap"
    fi
    if ! $mailimap; then
        echo "$pkg: failed to create IMAP home: $mailimap"
        exit 2
    fi
fi

# add user to mail lists and aliases
mailalias="ssh -x dsgmail /dsg/share/scripts/dsg-mailalias"
mailaliasrun=1

# see if there is a forwarding address
if [ "$forward" ]; then
    mailalias="$mailalias --forward=$forward"
    mailaliasrun=1
else
    mailalias="$mailalias -a"
fi
mailalias="$mailalias $login"
# only run if dsg for forwarding is needed
if [ "$mailaliasrun" ]; then
    if [ "$test" ]; then
        mailalias="echo $pkg: $mailalias"
    fi
    if ! $mailalias; then
        echo "$pkg: failed to add user to mail lists: $mailalias"
        exit 2
    fi
fi

# add user to samba smbpasswd file with default pass
samba="ssh -x mercury5 /dsg/share/scripts/dsg-samba $login"
if [ "$test" ]; then
    samba="echo $pkg: $samba"
fi
if ! $samba; then
    echo "$pkg: failed to create samba account: $mailimap"
    exit 2
fi

# mail user a welcome message
message=/dsg/share/dsg-login/welcome.email
if [ ! -f "$message" ]; then
    echo "$pkg: welcome message does not exist"
    exit 2
fi
if ! mailx -s 'Welcome to the DSG' "$login@dsgmail.wustl.edu" <$message; then
    echo "$pkg: unable to send email to $login"
    exit 2
fi

# Add user to gc.local AD, ldap must be done first.
userAD="/dsg/share/scripts/dsg-userAD -a $login"
if [ "$test" ]; then
    userADD="echo $pkg: $userAD"
fi
if $userAD; then
   echo "$pkg: user added to AD" 
else
    echo "$pkg: failed to add user to AD: $userAD"
    exit 2
fi

exit 0
