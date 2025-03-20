Minimal Scheduler
=================

In the following a short tutorial for creating a minimal scheduler written with sched_ext in C. 
This scheduler uses a global scheduling queue from which 
every CPU gets its tasks to run for a time slice. 
The scheduler order is First-In-First-Out. So it essentially implements a [round-robin scheduler](https://en.wikipedia.org/wiki/Round-robin_scheduling):

![Round Robin Diagram](https://github.com/parttimenerd/minimal-scheduler/raw/main/img/round_robin.png)

This short tutorial covers the basics; to learn more, visit the resources from the [scx wiki](https://github.com/sched-ext/scx/wiki).

Requirements
------------
We need a 6.12 kernel or a patched 6.11 kernel to build a custom scheduler.
You can get a kernel patched with the scheduler extensions on Ubuntu 24.10 from 
[here](https://launchpad.net/~arighi/+archive/ubuntu/sched-ext-unstable),
or you can use [CachyOS](https://cachyos.org/) and install a patched kernel from there.

Furthermore, you also need
- a recent `clang` for compilation
- `bpftool` for attaching the scheduler 

On Ubuntu, for example, you can run: `apt install clang linux-tools-common linux-tools-$(uname -r)`.

Nothing more is needed to run it, and you can find the code of this tutorial in the [minimal-scheduler](https://github.com/parttimenerd/minimal-scheduler) repository. I would advise to just cloning it:

```sh
git clone https://github.com/parttimenerd/minimal-scheduler
cd minimal-scheduler
```

The scheduler lives in the `sched_ext.bpf.c` file, but before we take a look at it,
I want to show you how you can use this scheduler:

Usage
-----

In short, we only need two steps:

```bash
# build and start the scheduler
./start.sh

# do something ...

# stop the scheduler
./stop.sh
```

I'll show you later what's in these scripts, but first, let's get to the scheduler code:

The Scheduler
-------------

_We assume that you have some experience writing eBPF programs. If not, Liz Rice's book [Learning eBPF](https://cilium.isovalent.com/hubfs/Learning-eBPF%20-%20Full%20book.pdf) is a good starting point._

The scheduler code only depends on the Linux bpf kernel headers and sched-ext. So here is the code from [`sched_ext.bpf.c`](https://github.com/parttimenerd/minimal-scheduler/blob/main/sched_ext.bpf.c):

```c
// This header is autogenerated, as explained later
#include "vmlinux.h"
// The following two headers come from the Linux headers library
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

// We use the new names from 6.13 to avoid confusion
#define scx_bpf_dsq_insert scx_bpf_dispatch
#define scx_bpf_dsq_insert_vtime scx_bpf_dispatch_vtime
#define scx_bpf_dsq_move_to_local scx_bpf_consume
#define scx_bpf_dsq_move scx_bpf_dispatch_from_dsq
#define scx_bpf_dsq_move_vtime scx_bpf_dispatch_vtime_from_dsq

// Define a shared Dispatch Queue (DSQ) ID
// We use this as our global scheduling queue
#define SHARED_DSQ_ID 0

// Two macros that make the later code more readable
// and place the functions in the correct sections
// of the binary file
#define BPF_STRUCT_OPS(name, args...)	\
    SEC("struct_ops/"#name)	BPF_PROG(name, ##args)

#define BPF_STRUCT_OPS_SLEEPABLE(name, args...)	\
    SEC("struct_ops.s/"#name)							      \
    BPF_PROG(name, ##args)

// Initialize the scheduler by creating a shared dispatch queue (DSQ)
s32 BPF_STRUCT_OPS_SLEEPABLE(sched_init) {
    // All scx_ functions come from vmlinux.h
    return scx_bpf_create_dsq(SHARED_DSQ_ID, -1);
}

// Enqueue a task to the shared DSQ that wants to run, 
// dispatching it with a time slice
int BPF_STRUCT_OPS(sched_enqueue, struct task_struct *p, u64 enq_flags) {
    // Calculate the time slice for the task based on the number of tasks in the queue
    // This makes the system slightly more responsive than a basic round-robin
    // scheduler, which assigns every task the same time slice all the time
    // The base time slice is 5_000_000ns or 5ms
    u64 slice = 5000000u / scx_bpf_dsq_nr_queued(SHARED_DSQ_ID);
    scx_bpf_dsq_insert(p, SHARED_DSQ_ID, slice, enq_flags);
    return 0;
}

// Dispatch a task from the shared DSQ to a CPU,
// whenever a CPU needs something to run, usually after it is finished
// running the previous task for the allotted time slice
int BPF_STRUCT_OPS(sched_dispatch, s32 cpu, struct task_struct *prev) {
    scx_bpf_dsq_move_to_local(SHARED_DSQ_ID);
    return 0;
}

// Define the main scheduler operations structure (sched_ops)
SEC(".struct_ops.link")
struct sched_ext_ops sched_ops = {
    .enqueue   = (void *)sched_enqueue,
    .dispatch  = (void *)sched_dispatch,
    .init      = (void *)sched_init,
    // There are more functions available, but we'll focus
    // on the important ones for a minimal scheduler
    .flags     = SCX_OPS_ENQ_LAST | SCX_OPS_KEEP_BUILTIN_IDLE,
    // A name that will appear in
    // /sys/kernel/sched_ext/root/ops
    // after we attached the scheduler
    // The name has to be a valid C identifier
    .name      = "minimal_scheduler"
};

// All schedulers have to be GPLv2 licensed
char _license[] SEC("license") = "GPL";
```

We can visualize the interaction of all functions in the scheduler with the following diagram:

![Scheduler Diagram](https://github.com/parttimenerd/minimal-scheduler/raw/main/img/scheduling.png)

Now, after you've seen the code,
run the [`start.sh`](https://github.com/parttimenerd/minimal-scheduler/blob/main/start.sh) script to generate the `vmlinux.h` BPF header
and then compile the scheduler code to BPF bytecode:

```bash
bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h
clang -target bpf -g -O2 -c sched_ext.bpf.c -o sched_ext.bpf.o -I.
```

And attach the scheduler using the `bpftool`:
```bash
bpftool struct_ops register sched_ext.bpf.o /sys/fs/bpf/sched_ext
```

The custom scheduler is now the scheduler of this system. You can check this
by accessing the `/sys/kernel/sched_ext/root/ops` file:

```bash
> ./scheduler.sh
# or
> cat /sys/kernel/sched_ext/root/ops
minimal_scheduler
```

And by checking `dmesg | tail`:

```bash
> sudo dmesg | tail
# ...
[32490.366637] sched_ext: BPF scheduler "minimal_scheduler" enabled
```

Play around with your system and see how it behaves.

There are three available schedulers:

- [`fifo.bpf.c`](https://github.com/parttimenerd/minimal-scheduler/blob/main/fifo.bpf.c) (also `sched_ext.bpf.c`) the before mentioned FIFO scheduler
- [`lotterly.bpf.c`](https://github.com/parttimenerd/minimal-scheduler/blob/main/lottery.bpf.c) a lottery scheduler as presented on [my blog](https://mostlynerdless.de/blog/2024/12/17/hello-ebpf-writing-a-lottery-scheduler-in-java-with-sched-ext-17/)

Try them via `./start.sh [scheduler file name]`.

If you're done, you can detach the scheduler by running the [`stop.sh`](https://github.com/parttimenerd/minimal-scheduler/blob/main/stop.sh) script
using root privileges. This removes the `/sys/fs/bpf/sched_ext/sched_ops` file.

Tasks for the Reader
--------------------

Now that you know what a basic scheduler looks like, you can start modifying it.
Here are a few suggestions:

### Vary the Time Slice
How does your system behave when you increase or decrease the time slice?

For example, try a time slice of 1s. Do you see any difference in how your cursor moves?
Or try a small time slice of 100us and run a program like that that does some computation, 
do you see a difference in its performance?

### Use a fixed Time Slice
How does your system behave when you change the scheduler to
use the same time slice, ignoring the number of enqueued processes?

Try, for example, to create load on your system and see how it behaves.

### Limit the Used CPUs
How does your system behave if the scheduler only schedules to specific CPUs?

Try, for example, to make your system effectively single-core by only consuming tasks
on CPU 0 in `sched_dispatch` (Hint: the `cpu` parameter is the CPU id).

### Create multiple Scheduling Queues
How does your system behave with multiple scheduling queues for different
CPUs and processes?

Try, for example, to create two scheduling queues, with one scheduling queue only
for a process with a specific id (Hint: `task_struct#tgid` gives you the process id)
which is scheduled on half of your CPUs.

Look into the [linux/sched.h](https://github.com/torvalds/linux/blob/ae90f6a6170d7a7a1aa4fddf664fbd093e3023bc/include/linux/sched.h#L778) header to learn more about `task_struct`. 

### Use more BPF features
If you already know how to write basic eBPF programs,
use `bpf_trace_printk` and the `running` and `stopping` hooks.

The `running` hook is called whenever a task starts running on a CPU; get the current CPU id via `smp_processor_id()`:

```c
int BPF_STRUCT_OPS(sched_running, struct task_struct *p) {
    // ...
    return 0; // there are no void functions in eBPF 
}
```

The `stopping` hook is called whenever a task stops running:

```c
int BPF_STRUCT_OPS(sched_stopping, struct task_struct *p, bool runnable) {
    // ...
    return 0;
}
```
You can use this to create visualizations of the scheduling order.

### Going Further

To do even more, you can look at the collected resources in the [scx wiki](https://github.com/sched-ext/scx/wiki),
especially the well-documented [sched-ext code in the kernel](https://github.com/torvalds/linux/blob/master/kernel/sched/ext.c).

If you're interested in how to use it in Rust, take a look at [scx](https://github.com/sched-ext/scx) and [scx_rust_scheduler](https://github.com/arighi/scx_rust_scheduler), and for Java at [hello-ebpf](https://mostlynerdless.de/blog/2024/09/10/hello-ebpf-writing-a-linux-scheduler-in-java-with-ebpf-15/).

License
-------
GPLv2
