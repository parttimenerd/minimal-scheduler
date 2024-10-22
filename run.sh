#!/bin/sh

# Register the scheduler
bpftool struct_ops register sched_ext.bpf.o /sys/fs/bpf/sched_ext

# Print scheduler name, fails if it isn't registered properly
cat /sys/kernel/sched_ext/root/ops