#!/bin/sh

# Usage: ./start.sh scheduler_file.c

# Build the scheduler if the C file is younger than the .c.o file or if the .c.o file doesn't exist
# use sched_ext.bpf.c as default
C_FILE=${1:-sched_ext.bpf.c}

# if --help is passed, print the usage

if [ "$1" = "--help" ]; then
    echo "Usage: ./start.sh scheduler_file.c"
    # print all the available scheduler files in the directory
    echo "Available scheduler files:"
    ls -1 *.bpf.c
    exit 0
fi

./build.sh $1

sudo ./stop.sh 


# Register the scheduler
sudo bpftool struct_ops register ${C_FILE}.o /sys/fs/bpf/sched_ext || (echo "Error attaching scheduler, consider calling stop.sh before" || exit 1)

# Print scheduler name, fails if it isn't registered properly
cat /sys/kernel/sched_ext/root/ops || (echo "No sched-ext scheduler installed" && exit 1)
