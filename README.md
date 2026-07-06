# GRR Scheduler — Linux Kernel Group Round-Robin Scheduling Class

An operating systems assignment implementing a custom Linux scheduling class,
**GRR (Group Round-Robin)**, that partitions CPUs between two task groups —
`DEFAULT` and `PERFORMANCE` — and lets userspace control both group
membership and per-group core allocation at runtime.


## Contents

| Path | Description |
|---|---|
| `hmwk2.patch` | Kernel patch implementing the GRR scheduling class |
| `grr_demo/` | Userspace demo/test harness for the two new syscalls |

## What the patch does

Applied on top of the mainline kernel, `hmwk2.patch` adds:

- **`kernel/sched/grr.c`** — a new scheduling class implementing group-aware
  round-robin scheduling, hooked into the core scheduler alongside CFS/RT.
- **`include/linux/sched/grr.h`** — GRR-specific task/group state.
- **Two new syscalls** (x86-64 table entries 467/468):
  - `sched_assign_ncores_to_group(int ncores, int group)` — sets how many
    CPUs are allocated to `group` (`DEFAULT` or `PERFORMANCE`), recomputes
    the group's CPU mask, and migrates any GRR task no longer running on a
    valid CPU for its group.
  - `sched_assign_process_to_group(pid_t pid, int group)` — moves every
    thread of the target process into `group`, migrating them onto a CPU
    valid for that group if needed.
- Supporting plumbing in `core.c`, `sched.h`, `init_task.c`, `kthread.c`,
  `Kconfig`, and the syscall tables.

Groups are strictly CPU-partitioned: increasing one group's core count
proportionally decreases the other's, and running GRR tasks are migrated
immediately to keep them on cores their group still owns.

## Demo (`grr_demo/`)

A small userspace harness for exercising the two syscalls:

| File | Purpose |
|---|---|
| `grr_worker.c` | CPU-bound busy-loop worker used as a GRR task |
| `assign_ncores.c` | CLI wrapper around `sched_assign_ncores_to_group` |
| `assign_process.c` | CLI wrapper around `sched_assign_process_to_group` |
| `demo_grr_answers.sh` | Full demo: spawns default/performance workloads under varying core splits and times them |
| `Makefile` | Builds the above and drives the demo |

Build and run (requires a kernel with the patch applied, booted, and root
for the syscalls):

```sh
cd grr_demo
make
sudo make run      # builds if needed, then runs demo_grr_answers.sh
```

`make info` reports the number of CPUs `nproc` sees on the current machine.

## Results

Three demo runs were taken, sweeping the DEFAULT/PERFORMANCE core split
(2/6, 4/4, 6/2 on an 8-core system) and timing four worker threads per
group:

| DEFAULT cores | PERFORMANCE cores | DEFAULT avg time | PERFORMANCE avg time |
|---:|---:|---:|---:|
| 2 | 6 | ~34.3s | ~6.3s |
| 4 | 4 | ~15.7s | ~6.5s |
| 6 | 2 | ~11.1s | ~12.8s |

Runtime tracks core allocation directly: whichever group holds more cores
finishes first, and the effect reverses cleanly when the split is reversed.
Daemon processes were also observed spreading across a wider CPU set as
their group's allocation grew, confirming the scheduler actively
rebalances tasks onto newly-available cores rather than only affecting new
task placement.

## Verification notes

- **Process → group assignment**: `heavy.c` blocks all worker threads on a
  condition variable until the parent calls `sched_assign_process_to_group`,
  so no thread runs before its group is set. The syscall updates every
  thread's group and migrates them onto a valid CPU. The consistent
  DEFAULT/PERFORMANCE timing gap confirms group assignment lands correctly
  before execution.
- **Core reallocation**: `sched_assign_ncores_to_group` recomputes both
  groups' CPU masks and migrates any GRR task left on a now-invalid CPU.
  Execution time for a group moves inversely with its core count across all
  three tested splits, matching the expected behavior.
- **Group prioritization**: PERFORMANCE consistently outruns DEFAULT
  whenever it holds more cores, and the advantage flips when the split is
  reversed — matching the intended group-based CPU partitioning.
- **Load balancing**: daemon CPU placement widens as a group's core count
  increases, consistent with `assign_ncores_to_group` actively migrating
  tasks into the updated mask rather than leaving them pinned.


