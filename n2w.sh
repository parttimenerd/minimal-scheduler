#!/bin/bash

# Compute the weight in p->scx.weight for a given nice value

# The weight is evaluated using this table https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/kernel/sched/core.c#n10122 
# and this function https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/kernel/sched/sched.h#n268
# 
# In practice weight = sched_weight_to_cgroup(sched_prio_to_weight[nice]) 
# so for example if you do the math when nice = 0 you get weight = 100 which is the default weight
#
# – Andrea Righi

# Nice value to weight mapping
weights=(
  88761 71755 56483 46273 36291
  29154 23254 18705 14949 11916
   9548  7620  6100  4904  3906
   3121  2501  1991  1586  1277
   1024   820   655   526   423
    335   272   215   172   137
    110    87    70    56    45
     36    29    23    18    15
)

CGROUP_WEIGHT_MIN=1
CGROUP_WEIGHT_DFL=100
CGROUP_WEIGHT_MAX=10000

# Function to compute cgroup weight from sched weight
compute_cgroup_weight() {
  local weight=$1
  local result=$(( (weight * CGROUP_WEIGHT_DFL + 512) / 1024 ))
  
  # Clamp the result
  if (( result < CGROUP_WEIGHT_MIN )); then
    result=$CGROUP_WEIGHT_MIN
  elif (( result > CGROUP_WEIGHT_MAX )); then
    result=$CGROUP_WEIGHT_MAX
  fi

  echo "$result"
}

# Main function
if [[ -z "$1" ]]; then
  echo "Usage: $0 <nice value (-20 to 19)>"
  exit 1
fi

nice_val=$1
if (( nice_val < -20 || nice_val > 19 )); then
  echo "Error: Nice value must be between -20 and 19"
  exit 1
fi

# Convert nice value to index
index=$(( nice_val + 20 ))
weight=${weights[$index]}
cgroup_weight=$(compute_cgroup_weight "$weight")

echo "$cgroup_weight"
