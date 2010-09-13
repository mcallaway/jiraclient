#! /bin/sh
# Activate and deactivate the visitor-type accounts.
# Copyright (C) 2005 Washington University in St. Louis
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
# testcheckin

# set up script
pkg=gsc-userlock
version=0.2

# set up defaults
login=visitor
action=lock
dir=archive
shell=/gsc/bin/bash
test=
passwd=passwd
rsh=rsh
usermod=usermod
userldap=/gsc/scripts/sbin/gsc-userldap
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
      --dir=* | --di=* | --d=*)
          dir="$optarg"
          ;;

      -d | --dir | --di | --d)
          prev_arg=dir
          ;;

      -h | --help | --hel | --he | --h)
          cat <<EOF
Usage: $pkg [OPTIONS]... [ACTION]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -d,--dir=ACTION    ACTION user home directory when locking, ACTION can be
                     keep, delete, or archive (default)
  -h,--help          print this message and exit
  -l,--login=LOGIN   reset account LOGIN rather than visitor
  -s,--shell=PATH    use shell PATH rather than /gsc/bin/bash when unlocking
  -t,--test          print out what would be done, but do not do it
  -v,--version       print version number and exit

This script activates or deactivates visitor-type accounts.  Possible
values for ACTION are lock and unlock.  lock is the default.

EOF
          exit 0;;

      --login=* | --logi=* | --log=* | --lo=* | --l=*)
          login="$optarg"
          ;;

      -l | --login | --logi | --log | --lo | --l)
          prev_arg=login
          ;;

      -t | --test | --tes | --te | --t)
          test=1
          ;;

      --shell=* | --shel=* | --she=* | --sh=* | --s=*)
          shell="$optarg"
          ;;

      -s | --shell | --shel | --she | --sh | --s)
          prev_arg=shell
          ;;

      -v | --version | --versio | --versi | --vers | --ver | --ve)
          echo "$pkg $version"
          exit 0;;

      -*)
          echo "$pkg: unrecognized option: $arg"
          echo "$pkg: Try '$pkg --help' for more information."
          exit 1;;

      *)
          action="$arg"
          ;;
  esac
done

# check that running on vm28
host=`hostname | sed 's/\..*//'`
if [ $host != vm28 ]; then
    echo "$pkg: not running on vm28: $host"
    exit 1
fi

# make sure this is being run as root
if [ -z "$test" ]; then
    # check that running as root
    if [ $(id -u) -ne 0 ]; then
        echo "$pkg: you are not root"
        exit 1
    fi
fi

# see if we are testing
if [ "$test" ]; then
    passwd="echo $pkg: passwd"
    rsh="echo $pkg: rsh"
    usermod="echo $pkg: usermod"
    userldap="echo $pkg: gsc-userldap"
fi

status=0
# alter the account
case "$action" in
    # lock
    L* | l*)
        # update ldap record
        if $userldap lock $login; then
            :
        else
            echo "$pkg: failed to update LDAP record: $?"
            status=1
        fi

        # make sure directory action is valiud
        case "$dir" in
            A* | a*)
                archive=/gsc/scripts/sbin/gsc-homearchive
                echo "$pkg: archiving $login home directory..."
                ;;
            D* | d*)
                archive="/gsc/scripts/sbin/gsc-homearchive --delete"
                ;;
            K* | k*)
                archive=
                ;;
            *)
                echo "$pkg: invalid directory action: $dir"
                echo "$pkg: keeping directory"
                archive=
                ;;
        esac

        # operate on the home directory
        if [ "$archive" ]; then
            # remove and recreate home directory
            if ssh -x linuscs65 $archive $login; then
                :
            else
                echo "$pkg: failed to clean $login home directory"
                exit 1
            fi

            # get necessary information to create home directory
            uid=`getent passwd|awk -F: "/^$login:/{print \\$3}"`
            if [ $? -ne 0 -o ! "$uid" ]; then
                echo "$pkg: unable to determine $login uid: $uid"
                exit 1
            fi
            gid=`getent passwd|awk -F: "/^$login:/{print \\$4}"`
            if [ $? -ne 0 -o ! "$gid" ]; then
                echo "$pkg: unable to determine $login gid: $gid"
                exit 1
            fi

            # create a new one
            if ssh -x linuscs65 /gsc/scripts/sbin/gsc-homedir --uid=$uid --gid=$gid $login; then
                :
            else
                echo "$pkg: unable to create new $login home directory"
                status=1
            fi
        else
            # if not removing, remove non-passwd authentication
            rmrsh="ssh -x linuscs65 /gsc/scripts/sbin/rm-rsh $login"
            if $rmrsh; then
                :
            else
                echo "$pkg: failed to remove $mach authentication tokens: $rmrsh"
                status=1
            fi
        fi
        ;;

    # unlock
    U* | u*)
        # get password
#        pw=`/gsc/bin/pwgen`
        pw=`pwgen`
        echo "$pkg: new password for $login account: $pw"

        # update ldap record
        if $userldap unlock $login $shell $pw; then
            :
        else
            echo "$pkg: failed to update LDAP record: $?"
            status=1
        fi
        ;;

    *)
        echo "$pkg: unrecognized action: $action"
        exit 1
        ;;
esac

# do not push changes if testing
if [ "$test" ]; then
    exit $status
fi

# check status
if [ "$status" -ne 0 ]; then
    echo "$pkg: THERE WERE ERRORS, PLEASE CORRECT"
fi
exit $status

# $Header$
