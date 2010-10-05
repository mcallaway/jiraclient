#!/bin/bash

# This script will setup the necessary dir layout and templates to start benchmarking an 
# application.  It assumes that the user will call the script as:
# create_benchmark.sh [appLICATION] [rt_ticket]
# Last modified 09/21/2010 by EMB

# Define some base variables
base=/gscmnt/gpfsdev1/benchmarking
pkg=`basename $0`
app=$1
rt_ticket=$2

# Exit if the app and rt ticket numbers are not passed to the script
if [ -z $1 ]; then
  echo "Usage: $PKG [APPLICATION] [RT_TICKET]"
  exit 1
fi

# Exit if the script is not called appropriately
if [ -z $2 ]; then
  echo "Usage: $PKG [APPLICATION] [RT_TICKET]"
  exit 1
fi

appbase=$base\/$app\_$rt_ticket

# Check if this already exists.
if [ -d $appbase ]; then
  echo "The dir $appbase already exists"
  exit 1
fi

# Set up our directories
mkdir -p $appbase\/bin
mkdir -p $appbase\/input
mkdir -p $appbase\/lsf
mkdir -p $appbase\/output

# Copy our execution script template into place
cp -af /gsc/scripts/bin/app_template.sh $appbase\/bin/$app\_benchmark.sh

# Copy our bsub script template into place:w
cp -af /gsc/scripts/bin/bsub_template.sh $appbase\/bin/bsub_$app\_benchmark.sh

# Replace appropriate variables in our execution script template
sed -i "s#BASE#$appbase#" $appbase\/bin/$app\_benchmark.sh
sed -i "s#APP#$app#" $appbase\/bin/$app\_benchmark.sh
sed -i "s#APP#$app#" $appbase\/bin/bsub_$app\_benchmark.sh
sed -i "s#BASE#$appbase#" $appbase\/bin/bsub_$app\_benchmark.sh

# Echo that we're done...giving instructions on how to proceed
echo
foo=$appbase\/bin/$app\_benchmark.sh
echo "LSF execution script $foo created.  Please review this script and adjust as necessary."
echo
foo=$appbase\/bin/bsub_$app\_benchmark.sh
echo "A default LSF submission script has also been created as $foo  By default it will specify a job with the max amount of ram on one of the servers in the benchmarking queue.  Once done reviewing these two scripts, execute $foo to start benchmarking."

echo
