#!/bin/bash
# SSH-resilient wrapper for performance tests
# This script provides automatic retry and keep-alive functionality

# Configuration
MAX_RETRIES=3
RETRY_DELAY=60
PROGRESS_FILE="/tmp/perf_test_progress"

# SSH options for keep-alive and resilience
SSH_OPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o ConnectTimeout=30 -o TCPKeepAlive=yes -o ExitOnForwardFailure=yes"

echo "=========================================="
echo "SSH-Resilient Performance Test Wrapper"
echo "=========================================="
echo "This wrapper provides automatic retry capability for SSH timeouts"
echo "Max retries: $MAX_RETRIES"
echo "Retry delay: $RETRY_DELAY seconds"
echo ""

# Function to execute command with retry logic
execute_with_retry() {
    local command="$1"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "$(date): Attempt $attempt of $MAX_RETRIES"
        echo "$(date): Executing: $command"
        
        # Record attempt start time
        echo "$(date): Starting attempt $attempt" >> "$PROGRESS_FILE"
        
        if eval "$command"; then
            echo "$(date): Command completed successfully"
            echo "$(date): Success on attempt $attempt" >> "$PROGRESS_FILE"
            return 0
        else
            local exit_code=$?
            echo "$(date): Command failed with exit code $exit_code"
            echo "$(date): Failed attempt $attempt (exit code: $exit_code)" >> "$PROGRESS_FILE"
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "$(date): Waiting $RETRY_DELAY seconds before retry..."
                sleep $RETRY_DELAY
            fi
        fi
        
        ((attempt++))
    done
    
    echo "$(date): All $MAX_RETRIES attempts failed"
    echo "$(date): All attempts exhausted" >> "$PROGRESS_FILE"
    return 1
}

# Function to check if original SSH command
if [[ "$1" == *"run-performance-tests.sh"* ]] || [[ "$1" == "./jmeter/run-performance-tests.sh" ]]; then
    echo "Detected performance test execution command"
    
    # Extract the original SSH command components
    if [[ "$0" == *"ssh"* ]]; then
        # Called from SSH - extract key file and host
        SSH_KEY=""
        SSH_HOST=""
        SSH_CMD=""
        
        # Parse arguments to extract SSH components
        while [[ $# -gt 0 ]]; do
            case $1 in
                -i)
                    SSH_KEY="$2"
                    shift 2
                    ;;
                -o)
                    # Skip SSH options
                    shift 2
                    ;;
                -T)
                    shift
                    ;;
                *)
                    if [[ -z "$SSH_HOST" && "$1" == *"@"* ]]; then
                        SSH_HOST="$1"
                        shift
                    elif [[ -z "$SSH_CMD" ]]; then
                        SSH_CMD="$*"
                        break
                    else
                        shift
                    fi
                    ;;
            esac
        done
        
        if [[ -n "$SSH_KEY" && -n "$SSH_HOST" && -n "$SSH_CMD" ]]; then
            enhanced_command="ssh -i '$SSH_KEY' $SSH_OPTS -o StrictHostKeyChecking=no -T '$SSH_HOST' '$SSH_CMD'"
        else
            enhanced_command="$SSH_CMD"
        fi
    else
        # Direct execution
        enhanced_command="$*"
    fi
    
    echo "Enhanced command with SSH keep-alive options"
    execute_with_retry "$enhanced_command"
else
    # Regular command execution
    execute_with_retry "$*"
fi
