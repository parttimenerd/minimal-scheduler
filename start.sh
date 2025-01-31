#!/bin/sh

# Usage: ./start.sh scheduler_file.c

# Build the scheduler if the C file is younger than the .c.o file or if the .c.o file doesn't exist
# use sched_ext.bpf.c as default
C_FILE=${1:-sched_ext.bpf.c}

./build.sh $1

./stop.sh 


# Register the scheduler
bpftool struct_ops register ${C_FILE}.o /sys/fs/bpf/sched_ext || (echo "Error attaching scheduler, consider calling stop.sh before" || exit 1)

# Print scheduler name, fails if it isn't registered properly
cat /sys/kernel/sched_ext/root/ops || (echo "No sched-ext scheduler installed" && exit 1)
