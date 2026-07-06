#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <limits.h>

#ifndef __NR_sched_assign_ncores_to_group
#define __NR_sched_assign_ncores_to_group 467
#endif

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <ncores> <group>\n", argv[0]);
        return EXIT_FAILURE;
    }

    char *endptr;

    long ncores = strtol(argv[1], &endptr, 10);
    if (*endptr != '\0' || ncores <= 0 || ncores > INT_MAX) {
        fprintf(stderr, "Invalid number of cores: %s\n", argv[1]);
        return EXIT_FAILURE;
    }

    long group = strtol(argv[2], &endptr, 10);
    if (*endptr != '\0' || (group != 1 && group != 2)) {
        fprintf(stderr, "Invalid group: %s (expected 1 or 2)\n", argv[2]);
        return EXIT_FAILURE;
    }

    int ret = syscall(__NR_sched_assign_ncores_to_group, (int)ncores, (int)group);
    if (ret != 0) {
        perror("sched_assign_ncores_to_group");
        return EXIT_FAILURE;
    }
    printf("Assigned %d cores to group %d\n", (int)ncores, (int)group);
    return EXIT_SUCCESS;
}
