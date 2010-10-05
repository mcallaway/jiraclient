#!/bin/bash

base=BASE
input=$base\/input
output=$base\/output
app="APP -i $input -o $output"

##### Do not modify below this line #####

# Exit if the input does not exist
if [ ! -e $input ]; then
  echo "ERROR: Input $input does not exist" 
  exit 99
fi

# Exit if the output does not exist
if [ ! -e $output ]; then
  echo "ERROR: Output $output does not exist"
  exit 99
fi

# Echo out our settings before execution
echo
echo "Input: $input"
echo "Output: $output"
echo "App: $app"
echo

/usr/bin/time -v $app
