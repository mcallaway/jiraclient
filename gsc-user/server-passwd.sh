#! /bin/sh
# Update passwd db on servers not running nis.
# Copyright (C) 2004 Washington University in St. Louis
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
pkg=server-passwd
version=0.1

test=
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
      -h | --help | --hel | --he | --h)
          cat <<EOF
Usage: $pkg [OPTIONS]...
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -h,--help      print this message and exit
  -t,--test      do not actually update hosts
  -v,--version   print version number and exit

EOF
          exit 0;;

      -t | --test | --tes | --te | --t)
          test=1
          ;;

      -v | --version | --versio | --versi | --vers | --ver | --ve | --v)
          echo "$pkg $version"
          exit 0;;

      -*)
          echo "$pkg: unrecognized option: $arg"
          echo "$pkg: Try '$pkg --help' for more information."
          exit 1;;

      *)
          echo "$pkg: too many parameters: $arg"
          echo "$pkg: Try '$pkg --help' for more information."
          exit 1;;
  esac
done

# list of users to push to servers
users='sshd|seqmgr|gelmover|achinwal|dbaisden|ddooling|ghu|hliu|irathore|jahmed|jrandolp|kcarpent|mnhan|pantonac|rwohlsta|syang'

# get salient passwd entries sorted by uid
entries=`ypcat passwd | grep -E "^($users):" | sort -t : -k 3 -n | sed -e 's/\(.\)$/\1\\\\/' -e '$s/\\\\$//'`
if [ $? != 0 ]; then
    echo "$pkg: failed to get password entries"
    exit 1
fi

# set up servers to hit
servers="3 5 6 7"
servers=3 # for initial testing
# only do one if testing
if [ "$test" ]; then
    servers=3
fi

# set default exit status
status=0

# loop through the machines
for n in $servers; do
    # machine name
    mach="nfs${n}maint"
    # set name of files
    passwd=/etc/passwd
    oldpasswd="/tmp/$pkg-$mach-$$"
    newpasswd="$oldpasswd-new"
    tmpfiles="$oldpasswd $newpasswd"

    # copy remote passwd file to local machine
    if rcp $mach:$passwd $oldpasswd; then
        :
    else
        echo "$pkg: failed to get passwd file from $mach"
        status=1
        continue
    fi

    # replace old contents with new
    if sed -e "/^sshd:/,\$c\\
$entries
" $oldpasswd >$newpasswd
        then
        :
    else
        echo "$pkg: failed to modify $oldpasswd"
        status=1
        continue
    fi

    # do not actually replace file if testing
    if [ "$test" ]; then
        echo "$pkg: new passwd file for $mach in $newpasswd"
        continue
    fi

    # see if the files are at all different
    if diff $oldpasswd $newpasswd >/dev/null; then
        # no difference
        rm $tmpfiles
        continue
    fi

    # make sure ownership is correct
    if chown root:sys $newpasswd; then
        :
    else
        echo "$pkg: failed to chmod $newpasswd"
        rm $tmpfiles
        status=1
        continue
    fi

    # put restrictive permissions on passwd file
    if chmod 444 $newpasswd; then
        :
    else
        echo "$pkg: failed to chmod $newpasswd"
        rm $tmpfiles
        status=1
        continue
    fi

    # make backup of old passwd file
    if rsh $mach cp $passwd $passwd.$pkg; then
        :
    else
        echo "$pkg: failed to move old passwd file"
        rm $tmpfiles
        status=1
        continue
    fi

    # copy new version over
    if rcp -p $newpasswd $mach:$passwd; then
        :
    else
        echo "$pkg: failed to copy $newpasswd to $mach"
        rm $tmpfiles
        status=1
        continue
    fi

    # create the shadow file from the passwd file
    if rsh $mach pwconv; then
        :
    else
        echo "$pkg: failed to create shadow file using pwconv"
        rm $tmpfiles
        status=1
        continue
    fi

    # remove temp files
    if rm $tmpfiles; then
        :
    else
        echo "$pkg: failed to remove temporary files: $tmpfiles"
        status=1
    fi
done

exit $status

# $Header: /var/lib/cvs/systems/user/server-passwd.sh,v 1.2 2004/07/19 21:42:53 ddooling Exp $
