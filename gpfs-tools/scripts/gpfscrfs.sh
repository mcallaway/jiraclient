#! /bin/bash

set -e

usage () {
  cat <<EOF
Usage: $0 <NAME> <NUMBER> [ARRAY]
Assign NUMBER free GPFS nsds to a filesystem named NAME.
Use array named ARRAY if specified.
EOF
  exit 1
}

die () {
  echo "$@"
  exit 1
}

yesorno () {
  ANSWER=Y
  read -n1 -e -p "OK? [Y|n] " ANSWER
  case "$ANSWER" in
    y|Y) echo "yes"
         return 0;
      ;;
    n|N) echo "no"
         return 1;
      ;;
      *) echo "Please answer y or n"
         yesorno
  esac
}

NAME="$1"
NUMBER="$2"
ARRAY="$3"

[ -n "$NAME" ] || usage
[ -n "$NUMBER" ] || usage
[ "$NUMBER" -eq "$NUMBER" 2>/dev/null ] || \
  die "$NUMBER is not a number"

MMLS=$( which mmlsnsd 2>/dev/null )
[ -n "$MMLS" ] || die "Cannot find mmlsnsd"
MMCR=$( which mmcrfs 2>/dev/null )
[ -n "$MMLS" ] || die "Cannot find mmcrfs"

ARG=$( mmlsnsd -F | sed -e '1,/^-*$/d' | awk "/$ARRAY/{print \$3}" | head -n $NUMBER | tr '\n' ';' )
[ -n "$ARG" ] || die "Error identifying free nsds"

CMD="$MMCR /vol/$NAME $NAME $ARG -A yes"

echo "About to run:"
echo $CMD
if yesorno ; then
  $CMD
  exit $?
else
  echo Aborted
fi
