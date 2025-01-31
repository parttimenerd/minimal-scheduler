#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define BPF_FOR_EACH_ITER (&___it)

// Define a shared Dispatch Queue (DSQ) ID
#define SHARED_DSQ_ID 0

#define BPF_STRUCT_OPS(name, args...)	\
    SEC("struct_ops/"#name)	BPF_PROG(name, ##args)

#define BPF_STRUCT_OPS_SLEEPABLE(name, args...)	\
    SEC("struct_ops.s/"#name)							      \
    BPF_PROG(name, ##args)

// We use the new names from 6.13 to make it more readable
#define scx_bpf_dsq_insert scx_bpf_dispatch
#define scx_bpf_dsq_insert_vtime scx_bpf_dispatch_vtime
#define scx_bpf_dsq_move_to_local scx_bpf_consume
#define scx_bpf_dsq_move scx_bpf_dispatch_from_dsq
#define scx_bpf_dsq_move_vtime scx_bpf_dispatch_vtime_from_dsq





// Initialize the scheduler by creating a shared dispatch queue (DSQ)
s32 BPF_STRUCT_OPS_SLEEPABLE(sched_init) {
    return scx_bpf_create_dsq(SHARED_DSQ_ID, -1);
}

// Enqueue a task to the shared DSQ, dispatching it with a time slice
int BPF_STRUCT_OPS(sched_enqueue, struct task_struct *p, u64 enq_flags) {
    // Calculate the time slice for the task based on the number of tasks in the queue
    u64 slice = 5000000u / scx_bpf_dsq_nr_queued(SHARED_DSQ_ID);
    scx_bpf_dsq_insert(p, SHARED_DSQ_ID, slice, enq_flags);
    return 0;
}

// Dispatch a task from the shared DSQ to a CPU
int BPF_STRUCT_OPS(sched_dispatch, s32 cpu, struct task_struct *prev) {
    struct task_struct *p;
	s32 random = bpf_get_prandom_u32() % scx_bpf_dsq_nr_queued(SHARED_DSQ_ID);
    bpf_for_each(scx_dsq, p, SHARED_DSQ_ID, 0) {
        random = random - 1;
        if (random <= 0) {
            if (scx_bpf_dispatch_from_dsq(BPF_FOR_EACH_ITER, p, 
            SCX_DSQ_LOCAL_ON | cpu, SCX_ENQ_PREEMPT)) {
                return 0;
            }
        }
    };
    return 0;
}





// Define the main scheduler operations structure (sched_ops)
SEC(".struct_ops.link")
struct sched_ext_ops sched_ops = {
    .enqueue   = (void *)sched_enqueue,
    .dispatch  = (void *)sched_dispatch,
    .init      = (void *)sched_init,
    .flags     = SCX_OPS_ENQ_LAST | SCX_OPS_KEEP_BUILTIN_IDLE,
    .name      = "lottery_scheduler"
};

// License for the BPF program
char _license[] SEC("license") = "GPL";
