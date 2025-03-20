#!/bin/bash

# Compute the closest nice value for a given weight


# Function to compute nice value from cgroup weight using n2w.sh
compute_nice_value() {
  local input_weight=$1
  local closest_nice=-20
  local min_diff=100000000

  for ((nice=-20; nice<=19; nice++)); do
    local weight=$(./n2w.sh "$nice")
    local diff=$(( input_weight - weight ))
    if (( diff < 0 )); then
      diff=$(( -diff ))
    fi
    if (( diff < min_diff )); then
      min_diff=$diff
      closest_nice=$nice
    fi
  done

  echo "$closest_nice"
}

# Main function
if [[ -z "$1" ]]; then
  echo "Usage: $0 <cgroup weight>"
  exit 1
fi

cgroup_weight=$1
nice_value=$(compute_nice_value "$cgroup_weight")

echo "$nice_value"
