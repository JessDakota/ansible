#!/usr/bin/env bash
#
# Gather KVM host performance metrics into timestamped logs.
# Original by JDB; sampler-style rewrite for headless collection.
#
# Usage: ./kvm-analyze.bash [-d DURATION] [-i INTERVAL] [-o OUTDIR]
#   -d  Duration in seconds (0 = run until Ctrl+C, default: 0)
#   -i  Sampling interval in seconds (default: 5)
#   -o  Output directory (default: ./performance_logs)
#   -h  Show this help

set -uo pipefail

INTERVAL=5
DURATION=0
LOG_DIR="./performance_logs"

usage() {
    sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":d:i:o:h" opt; do
    case "$opt" in
        d) DURATION=$OPTARG ;;
        i) INTERVAL=$OPTARG ;;
        o) LOG_DIR=$OPTARG ;;
        h) usage 0 ;;
        \?) echo "unknown option: -$OPTARG" >&2; usage 1 ;;
        :)  echo "option -$OPTARG requires an argument" >&2; usage 1 ;;
    esac
done

# kvm_stat and virsh need root. Prime sudo upfront so it doesn't prompt mid-run.
if ! sudo -v; then
    echo "error: sudo authentication required" >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
mkdir -p "$LOG_DIR"

KVM_STAT_LOG="$LOG_DIR/kvm_stat_$TIMESTAMP.log"
TOP_LOG="$LOG_DIR/top_$TIMESTAMP.log"
VMSTAT_LOG="$LOG_DIR/vmstat_$TIMESTAMP.log"
IOSTAT_LOG="$LOG_DIR/iostat_$TIMESTAMP.log"
VIRSH_LOG="$LOG_DIR/virsh_$TIMESTAMP.log"
META_LOG="$LOG_DIR/meta_$TIMESTAMP.log"

PIDS=()

have() { command -v "$1" >/dev/null 2>&1; }

start_bg() {
    local name=$1 logfile=$2
    shift 2
    echo "  starting $name -> $logfile"
    "$@" >"$logfile" 2>&1 &
    PIDS+=("$!")
}

start_sudo_bg() {
    local name=$1 logfile=$2
    shift 2
    echo "  starting $name (root) -> $logfile"
    sudo "$@" >"$logfile" 2>&1 &
    PIDS+=("$!")
}

# One-shot host metadata snapshot.
{
    echo "=== timestamp ==="; date -Iseconds
    echo "=== hostname ===";  hostname
    echo "=== uname ===";     uname -a
    echo "=== uptime ===";    uptime
    echo "=== cpu ===";       grep -m1 'model name' /proc/cpuinfo 2>/dev/null
                              nproc 2>/dev/null
    echo "=== memory ===";    free -h 2>/dev/null
    echo "=== block devs ==="; lsblk 2>/dev/null
    if have virsh; then
        echo "=== virsh list --all ==="
        sudo virsh list --all 2>/dev/null
        echo "=== virsh nodeinfo ==="
        sudo virsh nodeinfo 2>/dev/null
    fi
} > "$META_LOG" 2>&1
echo "wrote host metadata -> $META_LOG"

echo "starting collectors (interval=${INTERVAL}s)"

if have kvm_stat; then
    start_sudo_bg kvm_stat "$KVM_STAT_LOG" kvm_stat --interval "$INTERVAL"
else
    echo "  skip kvm_stat (not installed)" >&2
fi

if have top; then
    start_bg top "$TOP_LOG" top -b -d "$INTERVAL"
else
    echo "  skip top (not installed)" >&2
fi

# vmstat replaces htop — actually works headless and gives per-sample timestamps.
if have vmstat; then
    start_bg vmstat "$VMSTAT_LOG" vmstat -t "$INTERVAL"
else
    echo "  skip vmstat (not installed)" >&2
fi

if have iostat; then
    start_bg iostat "$IOSTAT_LOG" iostat -xt "$INTERVAL"
else
    echo "  skip iostat (install sysstat)" >&2
fi

# Per-VM domstats sampled at INTERVAL — the KVM-specific data the original missed.
if have virsh; then
    (
        while :; do
            date '+=== %F %T ==='
            sudo virsh list --state-running --name 2>/dev/null \
                | while read -r vm; do
                    [[ -z "$vm" ]] && continue
                    echo "--- domain: $vm ---"
                    sudo virsh domstats "$vm" 2>/dev/null
                done
            sleep "$INTERVAL"
        done
    ) > "$VIRSH_LOG" 2>&1 &
    PIDS+=("$!")
    echo "  starting virsh domstats sampler -> $VIRSH_LOG"
fi

if [[ ${#PIDS[@]} -eq 0 ]]; then
    echo "error: no collectors started" >&2
    exit 1
fi

cleanup() {
    trap '' SIGINT SIGTERM EXIT
    echo
    echo "stopping ${#PIDS[@]} collector(s)..."
    for pid in "${PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || sudo kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in "${PIDS[@]}"; do
        kill -KILL "$pid" 2>/dev/null || sudo kill -KILL "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    echo "logs saved in: $LOG_DIR"
    ls -1sh "$LOG_DIR"/*_"$TIMESTAMP".log 2>/dev/null || true
}

trap 'exit 130' SIGINT
trap 'exit 143' SIGTERM
trap cleanup EXIT

if (( DURATION > 0 )); then
    echo "monitoring for ${DURATION}s (Ctrl+C to stop early)"
    sleep "$DURATION"
else
    echo "monitoring started. Press Ctrl+C to stop."
    wait
fi
