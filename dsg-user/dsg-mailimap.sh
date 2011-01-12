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
pkg=dsg-mailimap
version=1.7

gid=
uid=
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
      -g | --gid | --gi | --g)
          prev_arg=gid
          ;;

      --gid=* | --gi=* | --g=*)
          gid="$optarg"
          ;;

      -h | --help | --hel | --he | --h)
          cat <<EOF
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -g,--gid=GID   set group ownership to GID
  -h,--help      print this message and exit
  -u,--uid=UID   set ownership to UID
  -v,--version   print version number and exit

This is meant to be called from gsc-useradd to create the user's home
directory.

EOF
          exit 0;;

      -u | --uid | --ui | --u)
          prev_arg=uid
          ;;

      --uid=* | --ui=* | --u=*)
          uid="$optarg"
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

# make sure we are on dsgmail server
host=$(hostname | sed 's/\..*//')
if [ $host != dsgmail ]; then
    echo "$pkg: not running on dsgmail: $host"
    exit 1
fi

# check command line parameters
if [ ! "$login" ]; then
    echo -n "$pkg:please enter login: "
    read login
fi
if [ ! "$uid" ]; then
    echo -n "$pkg:please enter uid: "
    read uid
fi
if [ ! "$gid" ]; then
    echo -n "$pkg:please enter gid: "
    read gid
fi

# create the home directory
home="/home/$login"
if mkdir $home; then
    :
else
    echo "$pkg:failed to create home directory:$home"
    exit 1
fi

# copy contents of skeleton dir
skel=/dsg/share/dsg-login/skel-mail
if [ ! -d "$skel" ]; then
    echo "$pkg:skeleton directory does not exist:$skel"
    exit 1
fi
if cp -r -p $skel/. $home; then
    :
else
    echo "$pkg:failed to copy contents of skeleton directory:$skel"
    exit 1
fi

# make sure home directory has correct permissions
if chmod 700 $home; then
    :
else
    echo "$pkg:failed to chmod home directory:$home"
    exit 1
fi

# change ownership and group of home directory
chown="chown -R -h $uid:$gid $home"
if $chown; then
    :
else
    echo "$pkg:failed to change ownership/group of home directory:$chown"
    exit 1
fi

# create the link to /dsguser
user="/dsguser/$login"
if ln -s $home $user; then
    :
else
    echo "$pkg:failed to create link from $home to $user"
    exit 1
fi

