#! /bin/bash
# Remove a user from GSC systems.
# Copyright (C) 2006 Washington University in St. Louis
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
pkg=dsg-userdel
version=1.5

login=
delete=
keep=
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
      -d | --delete | --delet | --dele | --del | --de | --d)
          delete="--delete"
          ;;

      -h | --help | --hel | --he | --h)
          cat <<EOF
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -d,--delete    delete home directory and mail rather than archive
  -h,--help      print this message and exit
  -k,--keep      do not archive user files
  -v,--version   print version number and exit

EOF
          exit 0;;

      -k | --keep | --kee | --ke | --k)
          keep=1
          ;;

      -v | --version | --versio | --versi | --vers | --ver | --ve)
          echo "$pkg $version"
          exit 0;;

      -*)
          echo "$pkg: unrecognized option: $arg"
          echo "$pkg: Try '$pkg --help' for more information."
          exit 1;;

      *)
          if [ "$login" ]; then
              echo "$pkg: you may create only one user per invokation"
              echo "$pkg: Try '$pkg --help' for more information."
              exit 1
          fi
          login="$arg"
          ;;
  esac
done

# check that running on goldn1
host=`hostname | sed 's/\..*//'`
if [ $host != goldn1 ]; then
    echo "$pkg: not running on goldn1: $host"
    exit 1
fi
# check that running as root
if [ $(id -u) -ne 0 ]; then
    echo "$pkg: you are not root"
    exit 1
fi

# make sure login was provided
if [ ! "$login" ]; then
    echo -n "$pkg: please enter login: "
    read login
fi

# exit status
status=0

# check to see if we should archive user files
if [ "$keep" ]; then
    # remove non-password authentication mechanisms
    rmssh="/dsg/share/scripts/rm-ssh $login"
    if $rmssh; then
        :
    else
        echo "$pkg: failed to remove $mach authentication tokens: $rmrsh"
        status=1
    fi
else
    # archive users home directory
    homearch="/dsg/share/scripts/dsg-homearchive $delete $login"
    if [ ! "$delete" ]; then
        echo "$pkg: archiving home directory..."
    fi
    if $homearch; then
        :
    else
        echo "$pkg: failed to archive home directory: $homearch"
        status=1
    fi

    # archive home directory on mail server
    imaparch="ssh -x dsgmail /dsg/share/scripts/dsg-mailarchive $delete $login"
    if [ ! "$delete" ]; then
        echo "$pkg: archiving mail on dsgmail..."
    fi
    if $imaparch; then
        :
    else
        echo "$pkg: failed to archive mail on dsgmail: $imaparch"
        status=1
    fi
fi


# remove user from mailing lists and aliases
rmalias="ssh -x dsgmail /dsg/share/scripts/rm-alias $login"
if $rmalias; then
    :
else
    echo "$pkg: failed to remove $login from mail lists/aliases: $rmalias"
    status=1
fi

# remove from ldap
userldap="/dsg/share/scripts/dsg-userldap delete $login"
if $userldap; then
    :
else
    echo "$pkg: failed to delete user from ldap: $userldap"
    status=1
fi

# remove from AD
userAD="/dsg/share/scripts/dsg-userAD -d $login"
if $userAD; then
   echo "$pkg: user deleted from AD"
else
    echo "$pkg: failed to delete user from AD: $userAD"
    status=1
fi

if [ "$status" -ne 0 ]; then
    echo "$pkg: THERE WERE ERRORS, PLEASE CORRECT"
fi

exit $status
