#! /bin/bash
# Remove non-password forms of authentication.
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
pkg=rm-ssh
version=1.7

login=
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
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -h,--help           print this message and exit
  -v,--version        print version number and exit

This is meant to be called from gsc-userdel to remove all non-password
authentication mechanisms.

EOF
          exit 0;;

      -v | --version | --versio | --versi | --vers | --ver | --ve | --v)
          echo "$pkg $version"
          exit 0;;

      -*)
          echo "$pkg:unrecognized option:$arg"
          echo "$pkg:Try '$pkg --help' for more information."
          exit 1;;

      *)
          if [ "$login" ]; then
              echo "$pkg:too many arguments:$arg"
              echo "$pkg:Try '$pkg --help' for more information."
              exit 1
          fi
          login="$arg"
          ;;
  esac
done

# read command line parameters
if [ ! "$login" ]; then
    echo -n "$pkg:please enter home directory: "
    read login
fi

# set home directory
home="/dsguser/$login"

# remove rhosts
rhosts="$home/.rhosts"
if [ -f "$rhosts" ]; then
    if rm $rhosts; then
        :
    else
        echo "$pkg:failed to remove $rhosts"
        exit 1
    fi
fi

# remove .ssh directory
ssh="$home/.ssh"
if [ -d "$ssh" ]; then
    if rm -r $ssh; then
	:
    else
	echo "$pkg:failed to remove $ssh"
	exit 1
    fi
fi

exit 0

# $Header: /var/lib/cvs/systems/user/rm-rsh.sh,v 1.2 2004/02/18 22:27:04 ddooling Exp $
