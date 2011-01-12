#! /bin/bash
# Remove user from mailing lists and aliases.
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
pkg=rm-alias
version=1.7

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

This is meant to be called from gsc-userdel to remove a user from
mailing lists and aliases.

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
              echo "$pkg: too many arguments: $arg"
              echo "$pkg: Try '$pkg --help' for more information."
              exit 1
          fi
          login="$arg"
          ;;
  esac
done

# make sure we are on dsgmail server
host=`hostname | sed 's/\..*//'`
if [ $host != dsgmail ]; then
    echo "$pkg: not running on dsgmail: $host"
    exit 1
fi

# set up path (mailman scripts)
PATH=/usr/lib/mailman/bin:$PATH
export PATH

# read command line parameters
if [ ! "$login" ]; then
    echo -n "$pkg: please enter login: "
    read login
fi

# track exit status
status=0

# remove from mailing lists
# get all lists
lists=`list_lists | awk 'NR > 1 {printf("%s ", $1)}'`
# loop through the lists
for list in $lists; do
    # see if email address is in list
    email=`list_members $list | grep "^$login@"`
    if [ $? -gt 1 ]; then
        echo "$pkg: failed to determine if $login subscribes to $list, skipping"
        continue
    fi
    if [ "$email" ]; then
        for e in $email; do
            # remove from list
            if remove_members $list $e; then
                :
            else
                echo "$pkg: failed to remove $e from $list"
                status=1
            fi
        done
    fi
done

# for now, no need to parse alias file so exit here

exit $status

# see if login is in aliases file
#alias=/etc/aliases
#if grep -q $login $alias; then
#    # back up aliases file
#    oldalias=$alias.bak
#    if cp $alias $oldalias; then
#        # safely remove login from aliases file
#        sed -n -e '${
## aliases file must have line at end that will not match any possible login
## print the line in the hold
#x
#p
## print the last line and exit
#g
#p
#q
#}
#' -e "/$login/{
## delete middle of multiline list
#/^  *$login,\$/n
## remove as end of multientry list
#/,$login\$/s///
## remove in middle of multientry list
#/$login,/s///
## delete at end of multiline list
#/^  *$login\$/{
## bring back previous line
#x
## remove comma at end
#s/,\$//
## put it back into hold
#h
#n
#}
#}
#" -e x -e '2,$p' $oldalias >$alias
#        if [ $? -ne 0 ]; then
#            echo "$pkg: failed to remove $login from $alias"
#            status=1
#        fi
#    else
#        echo "$pkg: failed to backup $alias to $oldalias"
#        status=1
#    fi
#fi
#
## remake alias database
#if newaliases; then
#    :
#else
#    echo "$pkg: failed to remake aliases database"
#    status=1
#fi
#
#if [ "$status" -ne 0 ]; then
#    echo "$pkg: THERE WERE ERRORS, PLEASE CORRECT"
#fi
#
#exit $status
