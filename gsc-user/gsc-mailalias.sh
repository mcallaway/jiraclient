#! /bin/sh
# Add user to mail lists and aliases.
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
pkg=gsc-mailalias
version=0.3

allgsc=
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
      -a | --allgsc | --allgs | --allg | --all | --al | --a)
          allgsc=1
          ;;

      -f | --forward | --forwar | --forwa | --forw | --for | --fo | --f)
          prev_arg=forward
          ;;

      --forward=* | --forwar=* | --forwa=* | --forw=* | --for=* | --fo=* | --f=*)
          forward="$optarg"
          ;;

      -h | --help | --hel | --he | --h)
	  cat <<EOF
Usage: $pkg [OPTIONS]... [LOGIN]
If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

Options:
  -a,--allgsc         subscribe user to allgsc mailing list
  -f,--forward=ADDR   forward all email to account to ADDR
  -h,--help           print this message and exit
  -v,--version        print version number and exit

This is meant to be called from gsc-useradd to create the user home
directory on the mail server and subscribe user to allgsc.

EOF
	  exit 0;;

      -v | --version | --versio | --versi | --vers | --ver | --ve | --v)
	  echo "$pkg $version"
	  exit 0;;

      -*)
	  echo "$pkg: unrecognized option: $arg"
	  echo "$pkg: Try '$pkg --help' for more information."
	  exit 1;;

      *)
          if [ "$login" ]; then
              echo "$pkg: too many arguments"
              echo "$pkg: Try '$pkg --help' for more information."
              exit 1
          fi
          login="$arg"
          ;;
  esac
done

# see if we should do anything
if [ ! "$forward" -a ! "$allgsc" ]; then
    echo "$pkg: nothing to do"
    exit 0
fi

# set path (for add_members)
PATH=/usr/sbin:/sbin:$PATH
export PATH

# make sure command line parameters got set
if [ ! "$login" ]; then
    echo -n "$pkg: please enter login: "
    read login
fi

# see if mail is going to be forwarded
if [ "$forward" ]; then
    alias=/etc/postfix/lists/external

    # add the forwarding address to the aliases file
    echo "$login: $forward" >>$alias
    if [ $? -ne 0 ]; then
        echo "$pkg: failed to add forward ($forward) to $alias"
        exit 1
    fi

    # push out the aliases
    if newaliases; then
        :
    else
        echo "$pkg: failed to remake aliases database"
        exit 1
    fi
fi

# subscribe user to allgsc mailing list
if [ "$allgsc" ]; then
    email=$login@genome.wustl.edu
    subscribe="add_members -r - allgsc"
    if echo $email | $subscribe; then
        :
    else
        echo "$pkg: failed to subscribe user to allgsc: $subscribe"
        exit 1
    fi
fi

exit 0
