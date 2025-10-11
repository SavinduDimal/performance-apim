#!/bin/bash
# Performance Test Progress Monitor
# This script monitors test progress and can help diagnose SSH timeout issues

PROGRESS_FILE="/tmp/perf_test_progress"
LOG_FILE="/tmp/perf_test_monitor.log"
CHECK_INTERVAL=300  # Check every 5 minutes
TIMEOUT_THRESHOLD=3600  # 1 hour timeout threshold

echo "=========================================="
echo "Performance Test Progress Monitor"
echo "=========================================="
echo "Monitoring progress file: $PROGRESS_FILE"
echo "Log file: $LOG_FILE" 
echo "Check interval: $CHECK_INTERVAL seconds"
echo "Timeout threshold: $TIMEOUT_THRESHOLD seconds"
echo ""

# Function to log with timestamp
log_message() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# Function to check test progress
check_progress() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        log_message "No progress file found - tests may not have started"
        return 0
    fi
    
    # Get last activity timestamp
    last_activity=$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    time_diff=$((current_time - last_activity))
    
    log_message "Last activity: $(date -d @$last_activity)"
    log_message "Time since last activity: $time_diff seconds"
    
    if [[ $time_diff -gt $TIMEOUT_THRESHOLD ]]; then
        log_message "WARNING: No progress for $time_diff seconds (threshold: $TIMEOUT_THRESHOLD)"
        log_message "This may indicate an SSH timeout or stuck test"
        
        # Show last few lines of progress file
        log_message "Last progress entries:"
        tail -n 10 "$PROGRESS_FILE" | while read line; do
            log_message "  $line"
        done
        
        return 1
    fi
    
    return 0
}

# Function to show test statistics
show_stats() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi
    
    local total_attempts=$(grep -c "Starting attempt" "$PROGRESS_FILE" 2>/dev/null || echo 0)
    local successful_attempts=$(grep -c "Success on attempt" "$PROGRESS_FILE" 2>/dev/null || echo 0)
    local failed_attempts=$(grep -c "Failed attempt" "$PROGRESS_FILE" 2>/dev/null || echo 0)
    
    log_message "Test Statistics:"
    log_message "  Total attempts: $total_attempts"
    log_message "  Successful: $successful_attempts" 
    log_message "  Failed: $failed_attempts"
}

# Main monitoring loop
log_message "Starting performance test monitoring"

if [[ "$1" == "--daemon" ]]; then
    log_message "Running in daemon mode"
    while true; do
        check_progress
        show_stats
        sleep $CHECK_INTERVAL
    done
else
    log_message "Running single check"
    check_progress
    show_stats
    
    # If provided with --wait option, monitor until tests complete
    if [[ "$1" == "--wait" ]]; then
        log_message "Waiting for tests to complete..."
        while true; do
            if check_progress; then
                sleep $CHECK_INTERVAL
            else
                log_message "Tests appear to be stuck - consider manual intervention"
                break
            fi
        done
    fi
fi

log_message "Monitoring complete"
