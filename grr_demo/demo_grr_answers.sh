#!/bin/bash
set -euo pipefail

YELLOW='\033[0;33m'
NC='\033[0m'   # No Color (reset)

SCHED_GRR=8
RETRY_COUNT=5
RETRY_DELAY=1

cleanup() {
    [[ -n "${worker_pid:-}" ]] && kill "$worker_pid" 2>/dev/null || true
}
trap cleanup EXIT

cpu_range_to_list() {
    local range=$1
    local list=()
    IFS=',' read -ra parts <<< "$range"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start=${BASH_REMATCH[1]}
            local end=${BASH_REMATCH[2]}
            for ((i=start; i<=end; i++)); do
                list+=($i)
            done
        else
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                list+=($part)
            else
                echo -e "${YELLOW}Warning:${NC} Invalid CPU range part '$part' ignored." >&2
            fi
        fi
    done
    echo "${list[@]}"
}

get_policy() {
    local pid=$1
    if [[ ! -r "/proc/$pid/stat" ]]; then
        echo "-1"
        return
    fi
    local policy=$(awk '{if (NF>=41) print $41; else print "-1"}' "/proc/$pid/stat" 2>/dev/null || echo "-1")
    echo "$policy"
}

parse_taskset_cpu_list() {
    local pid=$1
    local cpu_list

    if ! cpu_list=$(taskset -cp "$pid" 2>/dev/null | grep -oP 'affinity list: \K.*'); then
        echo ""
        return 1
    fi

    echo "$cpu_list"
}


check_command() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command '$cmd' not found." >&2
        exit 1
    fi
}

check_command cat
check_command awk
check_command taskset
check_command sudo
check_command grep

echo "========== CPU Info =========="
present_range=$(cat /sys/devices/system/cpu/present || { echo "Failed to read present CPUs"; exit 1; })
online_range=$(cat /sys/devices/system/cpu/online || { echo "Failed to read online CPUs"; exit 1; })

present_cpus=($(cpu_range_to_list "$present_range"))
online_cpus=($(cpu_range_to_list "$online_range"))

if [[ ${#online_cpus[@]} -eq 0 ]]; then
    echo "Error: No CPUs online!" >&2
    exit 1
fi

echo "CPUs present (${#present_cpus[@]}): ${present_cpus[*]}"
echo "CPUs online (${#online_cpus[@]}): ${online_cpus[*]}"
echo "============================="

half_count=$(( ${#online_cpus[@]} / 2 ))
group1_cores=("${online_cpus[@]:0:half_count}")
group2_cores=("${online_cpus[@]:half_count}")

echo -e "\n========== Test 1: Assign ncores to Groups =========="
echo "Group 1 (GRR_DEFAULT) expected CPUs: ${group1_cores[*]}"
echo "Group 2 (GRR_PERFORMANCE) expected CPUs: ${group2_cores[*]}"
echo

for attempt in $(seq 1 $RETRY_COUNT); do
    if sudo ./assign_ncores "${#group1_cores[@]}" 1; then
        echo "Assigned ${#group1_cores[@]} cores to group 1 and the rest to group 2 successfully (attempt $attempt)."
        break
    else
        echo -e "${YELLOW}Warning:${NC} assign_ncores failed (attempt $attempt), retrying..." >&2
        sleep $RETRY_DELAY
    fi
    [[ $attempt -eq $RETRY_COUNT ]] && { echo "Failed to assign ncores after $RETRY_COUNT attempts." >&2; exit 1; }
done


echo -e "\n========== Test 2: Assign Processes to Groups =========="
echo "Launching worker..."
./grr_worker &
worker_pid=$!

if ! kill -0 "$worker_pid" 2>/dev/null; then
    echo "Error: Failed to start grr_worker." >&2
    exit 1
fi
echo "Worker started on PID $worker_pid"

echo "Assigning worker PID $worker_pid to group 1 (GRR_DEFAULT)..."
if ! sudo ./assign_process "$worker_pid" 1; then
    echo -e "${YELLOW}Warning:${NC} assign_process for worker failed." >&2
else
    echo "Assigned worker PID $worker_pid to group 1."
fi

worker_policy=$(get_policy "$worker_pid")
echo "Worker PID $worker_pid scheduling policy: $worker_policy"

sleep $RETRY_DELAY

if [[ "$worker_policy" -ne $SCHED_GRR ]]; then
    echo "Worker PID $worker_pid not under SCHED_GRR, skipping affinity checks."
else
    actual_affinity=$(parse_taskset_cpu_list "$worker_pid") || actual_affinity=""
    echo "Affinity CPUs: $actual_affinity"

    if [[ -z "$actual_affinity" ]]; then
        echo -e "${YELLOW}Warning:${NC} Could not parse CPU affinity for worker PID $worker_pid. Expected CPUs: ${group1_cores[*]}, Policy: $worker_policy"
    else
        affinity_list=($(cpu_range_to_list "$actual_affinity"))
        local_fail=0
        for cpu in "${affinity_list[@]}"; do
            if ! [[ " ${group1_cores[*]} " == *" $cpu "* ]]; then
                echo -e "${YELLOW}Warning:${NC} CPU $cpu in worker affinity is NOT in expected GRR_DEFAULT CPUs!"
                local_fail=1
            fi
        done
        if [[ $local_fail -eq 0 ]]; then
            echo "Worker CPU affinity matches expected GRR_DEFAULT CPUs."
        fi
    fi
fi

echo -e "\nAssigning current shell PID $$ to group 2 (GRR_PERFORMANCE)..."
if ! sudo ./assign_process $$ 2; then
    echo -e "${YELLOW}Warning:${NC} assign_process for shell failed." >&2
else
    echo "Assigned shell PID $$ to group 2."
fi

shell_policy=$(get_policy $$)
echo "Shell PID $$ scheduling policy: $shell_policy"

sleep $RETRY_DELAY

if [[ "$shell_policy" -ne $SCHED_GRR ]]; then
    echo "Shell PID $$ not under SCHED_GRR, skipping affinity checks."
else
    actual_affinity=$(parse_taskset_cpu_list $$) || actual_affinity=""
    echo "Affinity CPUs: $actual_affinity"

    if [[ -z "$actual_affinity" ]]; then
        echo -e "${YELLOW}Warning:${NC} Could not parse CPU affinity for shell PID $$. Expected CPUs: ${group2_cores[*]}, Policy: $shell_policy"
    else
        affinity_list=($(cpu_range_to_list "$actual_affinity"))
        local_fail=0
        for cpu in "${affinity_list[@]}"; do
            if ! [[ " ${group2_cores[*]} " == *" $cpu "* ]]; then
                echo -e "${YELLOW}Warning:${NC} CPU $cpu in shell affinity is NOT in expected GRR_PERFORMANCE CPUs!"
                local_fail=1
            fi
        done
        if [[ $local_fail -eq 0 ]]; then
            echo "Shell CPU affinity matches expected GRR_PERFORMANCE CPUs."
        fi
    fi
fi

kill "$worker_pid"

echo -e "\nDemo completed!"
