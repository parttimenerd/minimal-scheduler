#!/bin/sh

# Create the vmlinux header with all the eBPF Linux functions
bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

# Compile the scheduler
clang -target bpf -g -O2 -c sched_ext.bpf.c -o sched_ext.bpf.o -I.