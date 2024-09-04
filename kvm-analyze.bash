#!/bin/bash

# Script by JDB to gather performance metrics using kvm_stat, top, htop, and iostat

# Create a directory to store the logs
LOG_DIR="./performance_logs"
mkdir -p $LOG_DIR

# Define log file names with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
KVM_STAT_LOG="$LOG_DIR/kvm_stat_$TIMESTAMP.log"
TOP_LOG="$LOG_DIR/top_$TIMESTAMP.log"
HTOP_LOG="$LOG_DIR/htop_$TIMESTAMP.log"
IOSTAT_LOG="$LOG_DIR/iostat_$TIMESTAMP.log"

# Function to run kvm_stat
run_kvm_stat() {
    echo "Running kvm_stat..."
    sudo kvm_stat --interval 5 > $KVM_STAT_LOG &
    KVM_PID=$!
}

# Function to run top
run_top() {
    echo "Running top..."
    top -b -d 5 > $TOP_LOG &
    TOP_PID=$!
}

# Function to run htop
run_htop() {
    echo "Running htop..."
    htop > $HTOP_LOG &
    HTOP_PID=$!
}

# Function to run iostat
run_iostat() {
    echo "Running iostat..."
    iostat -x 5 > $IOSTAT_LOG &
    IOSTAT_PID=$!
}

# Start monitoring tools
run_kvm_stat
run_top
run_htop
run_iostat

# Function to stop all monitoring tools
stop_monitoring() {
    echo "Stopping monitoring tools..."
    kill $KVM_PID
    kill $TOP_PID
    kill $HTOP_PID
    kill $IOSTAT_PID
    echo "Logs are saved in $LOG_DIR"
}

# Trap Ctrl+C (SIGINT) and call stop_monitoring to clean up
trap stop_monitoring SIGINT

# Wait for user to terminate the script
echo "Monitoring started. Press Ctrl+C to stop."
wait
