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
pkg=dsg-passwd
version=1.5

# loop through positional parameters
oldpass=
newpass=
login=
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
  -n,--newpass=	      new password for account
  -o,--oldpass=	      old password on account
  -h,--help           print this message and exit
  -v,--version        print version number and exit

This is meant to be called from web frontend for user to
change their passwords

EOF
          exit 0;;

      -n)
	  prev_arg=newpass
	  ;;

      --newpass=*)
	  newpass="$optarg"
	  ;;

      -o)
	  prev_arg=oldpass
	  ;;

      --oldpass=*)
	  oldpass="$optarg"
	  ;;

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

# change ldap passwd
if ! ldappasswd -a $oldpass -s $newpass -h ldap.dsg.wustl.edu -D "uid=$login,ou=People,dc=dsg,dc=wustl,dc=edu" -x -w $oldpass -ZZ >/dev/null 2>&1; then
	echo "$pkg: failed to change passwd in ldap"
	exit 2
fi

# hack to update shadowLastChange because ldappasswd failes to do it
if ! ssh -x -i /var/www/.ssh/chpass.key root@dsgmail "echo $newpass | passwd --stdin $login" >/dev/null 2>&1; then
	echo "$pkg: failed to change shadowLastChange in ldap"
        exit 2
fi

# change samba passwd
if ! ssh -x -i /var/www/.ssh/chpass.key root@mercury5 "echo -e \"$newpass\n$newpass\" | smbpasswd -s $login"; then
	echo "$pkg: failed to change smbpasswd in samba"
	exit 2
fi
