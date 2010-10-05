#!/bin/bash

base=BASE
app=APP
lsfoutdir=$base/lsf

##### Do not modify below this line #####

# Exit if the lsfoutput location does not exist
if [ ! -e $lsfoutdir ]; then
  echo "ERROR: The LSF output dir $lsfoutdir does not exist" 
  exit 1
fi

# Echo out our settings before execution
#echo "Input: $input"

# Submit our job
bsub -q benchmarking -n 8 -M 48234496 -J $app -R 'select[type==LINUX64 && mem>47104] rusage[mem=47104] span[hosts=1]' -oo $lsfoutdir/%J.out $base\/bin/$app\_benchmark.sh
