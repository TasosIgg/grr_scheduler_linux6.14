#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>

#ifndef __NR_sched_assign_process_to_group
#define __NR_sched_assign_process_to_group 468
#endif

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <pid> <group>\n", argv[0]);
        return 1;
    }
    pid_t pid = (pid_t)atoi(argv[1]);
    int group = atoi(argv[2]);

    int ret = syscall(__NR_sched_assign_process_to_group, pid, group);
    if (ret != 0) {
        perror("sched_assign_process_to_group");
        return 1;
    }
    return 0;
}
