#! /bin/bash
#
# Quickie script to ask RTM DB about the state
# of hosts in a host group:
# How many slots are open in the host group with
# memory X and slots Y?
#
# Relies on /gsc/scripts/bin/rtm_sqlrun

CMD=/gsc/scripts/bin/rtm_sqlrun

HG=$1
MEM=${2:-0}
SLOTS=${3:-0}

usage () {
  echo "usage: $0 <hostgroup> [mem] [slots]"
  exit 1
}

[ -z "$HG" ] && \
  usage;

$CMD "
SELECT
  gh.host as host,
  ghg.groupName as hostgroup,
  gl.mem as memory,
  ( gh.maxJobs - gh.numJobs ) as open_slots,
  ( gh.numJobs / gh.maxJobs ) as capacity
  FROM grid_load as gl
  LEFT JOIN grid_hosts as gh
  ON gh.host = gl.host
  LEFT JOIN grid_hostgroups as ghg
  ON gh.host = ghg.host
  HAVING ghg.groupName = \"$HG\"
  AND gl.mem >= $MEM
  AND open_slots >= $SLOTS
  ORDER BY open_slots DESC, memory DESC
"
