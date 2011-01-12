#! /bin/bash
# Create user's home directory.
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
pkg=dsg-samba
version=1.7

login=
homevol=
del=
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

      -d | --delete)
	del=1
	;;

      -h | --help | --hel | --he | --h)
	  cat <<EOF
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -d,--delete	 delete samba passwd instead of adding
  -h,--help      print this message and exit
  -v,--version   print version number and exit

This is meant to be called from gsc-useradd to create the user's home
directory.

EOF
	  exit 0
	;;


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

# check command line parameters
if [ ! "$login" ]; then
    echo -n "$pkg:please enter login: "
    read login
fi

# login to mercury5 and add/delete smbpasswd
if [ "$del" ]; then
	smbpass="smbpasswd -x $login"
else
	smbpass="smbpasswd -s -a $login"
fi
if ! $smbpass < /root/defaultsmb.pass; then
	echo "$pkg: failed to add/remove $login to smbpasswd on mercury5"
	exit 2
fi

exit 0
