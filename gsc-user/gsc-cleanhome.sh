#! /bin/sh
# clean the kde/gnome files from a users home directory
# must run the script as the user

pkg=gsc-cleanhome
version=0.6
fontconfdir=/gsc/scripts/share/systemimager

# process positional parameters
save=1
test=
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

Synopsis: $pkg removes old configuration files from a user home directory

Options:
  -h,--help      print this message and exit
  -r,--remove    delete files
  -s,--save      do not delete files, move them out of the way (default)
  -t,--test      do not do anything, just print what would be done
  -v,--version   print version number and exit

EOF
          exit 0;;

      -r | --remove | --remov | --remo | --rem | --re | --r)
          save=
          ;;

      -s | --save | --sav | --sa | --s)
          save=1
          ;;

      -t | --test | --tes | --te | --t)
          test=echo
          ;;

      -v | --version | --versio | --versi | --vers | --ver | --ve | --v)
          echo "$pkg $version"
          exit 0;;

      -*)
          echo "$pkg: unknown option: $arg"
          echo "$pkg: Try \`$pkg --help' for more information."
          exit 1;;

      *)
          echo "$pkg: ignoring command line argument: $arg"
          ;;
  esac
done

# change to home directory
if cd $HOME; then
    :
else
    echo "$pkg: failed to change to home directory: $HOME"
    exit 1
fi

# see what we are doing to the files
action=remove
cmd='rm -rf'
if [ "$save" ]; then
    action=move
    save="$pkg-$$"

    # create new directory for files
    if mkdir $save; then
        :
    else
        echo "$pkg: failed to make directory: $save"
        exit 1
    fi
    cmd="mv"
fi

echo "$pkg: you are about to $action kde/gnome files from directory: $HOME"
echo -n "$pkg: press y to continue: "
read answer
case "$answer" in
    [Yy]*)
        :
        ;;
    *)
        exit 0
        ;;
esac

# configuration files
configs=".cache .config .dmrc .fonts* .gconf* .gnome* .gstreamer* .gtk* .icons* .kde* .kpackage .local .lpoptions .mcop* .metacity .nautilus .qt* .recently-used .ssh/known_hosts* .thumbnails .tora* .xscreensaver .xsession* Desktop GNUstep"

# exit status
status=0

# loop through the configuation files
for config in $configs; do
    if [ -f "$config" -o -d "$config" ]; then
        if $test $cmd $config $save; then
            :
        else
            echo "$pkg: command failed: $cmd $config $save"
            status=2
        fi
    fi
done

if [ "$status" -eq 0 ]; then
    echo "$pkg: config files have been ${action}d"
else
    echo "$pkg: there were problems cleaning $HOME"
    echo "$pkg: some configuration files may remain"
fi

# let them know where files were moved
if [ "$save" ]; then
    echo "$pkg: old configuration files moved to: $save"
fi

# copy the default KDE .fonts.conf to turn on sub-hinting for Flatscreens
if cp $fontconfdir/.fonts.conf .; then
     :
else
     echo "$pkg: cannot copy $fontconfdir/.fonts.conf to $HOME"
fi

exit $status
