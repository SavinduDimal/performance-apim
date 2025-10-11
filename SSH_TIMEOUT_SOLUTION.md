# SSH Timeout Solution for Performance Tests

## Problem Description

The WSO2 APIM Docker performance tests are failing due to SSH session timeouts after approximately 1 hour of execution. The error occurs with the command:

```bash
ssh -i /home/ubuntu/keys/apim-perf-test2.pem -o StrictHostKeyChecking=no -T ubuntu@18.212.130.77 ./jmeter/run-performance-tests.sh
```

Only 4 out of 8 test scenarios complete before the SSH connection times out, preventing the full test suite from running.

## Root Cause

The issue is caused by:
1. **SSH Session Timeout**: Default SSH configurations don't maintain keep-alive for long-running sessions
2. **Network Timeouts**: Cloud network infrastructure may drop idle connections
3. **No Resume Capability**: Tests restart from the beginning when SSH reconnects

## Solutions Implemented

### 1. SSH Keep-Alive Configuration

Enhanced all SSH and SCP commands in `run-performance-tests.sh` with keep-alive options:

```bash
# SSH options added:
-o ServerAliveInterval=60      # Send keep-alive every 60 seconds
-o ServerAliveCountMax=3       # Allow 3 missed keep-alives (3 minutes)  
-o ConnectTimeout=30           # Set initial connection timeout
-o TCPKeepAlive=yes           # Enable TCP keep-alive
```

**Files Modified:**
- `distribution/scripts/jmeter/run-performance-tests.sh`
  - `before_execute_test_scenario()` function
  - `initialize()` function

### 2. Test Resume Capability  

Created `resume-performance-tests.sh` to automatically resume interrupted tests:

**Features:**
- Detects completed scenarios by checking result files
- Skips already completed scenarios
- Continues from where tests left off
- Provides progress reporting

**Usage:**
```bash
# If tests get interrupted, run:
./resume-performance-tests.sh [original_parameters]
```

### 3. SSH Resilient Wrapper

Created `ssh-resilient-wrapper.sh` with automatic retry logic:

**Features:**
- Automatic retry on SSH failures (max 3 attempts)
- Enhanced SSH keep-alive options
- Progress tracking and logging
- Configurable retry delays

### 4. Progress Monitoring

Created `monitor-test-progress.sh` to track test execution:

**Features:**
- Real-time progress monitoring
- Timeout detection (1-hour threshold)
- Test statistics reporting
- Daemon mode for continuous monitoring

**Usage:**
```bash
# Single check
./monitor-test-progress.sh

# Continuous monitoring  
./monitor-test-progress.sh --daemon

# Wait for completion
./monitor-test-progress.sh --wait
```

## Implementation Changes Summary

### Modified Files:
1. **`run-performance-tests.sh`**
   - Added SSH keep-alive options to all SSH/SCP commands
   - Added resume capability detection
   - Enhanced error handling for Docker deployments

2. **`apim-start.sh`** (previously modified)
   - Improved Docker deployment detection
   - Enhanced error handling with set +e/set -e patterns
   - Better exit status management

### New Files Created:
1. **`resume-performance-tests.sh`** - Test resumption capability
2. **`ssh-resilient-wrapper.sh`** - SSH retry wrapper  
3. **`monitor-test-progress.sh`** - Progress monitoring
4. **`SSH_TIMEOUT_SOLUTION.md`** - This documentation

## Deployment Instructions

### For Jenkins/CloudFormation Environment:

1. **Update the CloudFormation orchestration command** to use enhanced SSH options:

   **Current command:**
   ```bash
   ssh -i /home/ubuntu/keys/apim-perf-test2.pem -o StrictHostKeyChecking=no -T ubuntu@18.212.130.77 ./jmeter/run-performance-tests.sh
   ```

   **Enhanced command:**
   ```bash
   ssh -i /home/ubuntu/keys/apim-perf-test2.pem -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o ConnectTimeout=30 -o TCPKeepAlive=yes -T ubuntu@18.212.130.77 ./jmeter/run-performance-tests.sh
   ```

2. **Or use the resilient wrapper:**
   ```bash
   ssh -i /home/ubuntu/keys/apim-perf-test2.pem -o StrictHostKeyChecking=no -T ubuntu@18.212.130.77 ./jmeter/ssh-resilient-wrapper.sh ./jmeter/run-performance-tests.sh
   ```

### For Manual Testing:

1. **Start with progress monitoring:**
   ```bash
   ./monitor-test-progress.sh --daemon &
   ```

2. **Run tests with enhanced SSH:**
   ```bash
   ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o ConnectTimeout=30 ubuntu@target-host ./jmeter/run-performance-tests.sh [parameters]
   ```

3. **If tests are interrupted, resume:**
   ```bash
   ./resume-performance-tests.sh [original_parameters]
   ```

## Expected Results

With these improvements:

1. **SSH sessions should maintain connectivity** for the full 2+ hour test duration
2. **All 8 test scenarios should complete** (4 passthrough + 4 transformation)
3. **Automatic recovery** from temporary network issues
4. **Resume capability** if tests are still interrupted
5. **Better monitoring** and diagnostics

## Testing Parameters

The tests should now successfully process all combinations:
- Users: 100, 200
- Message sizes: 1024B, 10240B  
- Scenarios: passthrough, transformation
- Total scenarios: 2 × 2 × 2 = 8 scenarios

## Troubleshooting

### If SSH still times out:
1. Check network connectivity between Jenkins and target instances
2. Verify security group rules allow persistent connections
3. Consider using session multiplexing: `-o ControlMaster=auto -o ControlPath=/tmp/%r@%h:%p -o ControlPersist=600`

### If tests still fail:
1. Check progress monitoring logs: `/tmp/perf_test_monitor.log`
2. Review progress file: `/tmp/perf_test_progress`
3. Use resume capability: `./resume-performance-tests.sh`

### For debugging:
1. Enable SSH debugging: Add `-vv` to SSH commands
2. Monitor network connections: `netstat -an | grep :22`
3. Check system resources: `top`, `free -h`, `df -h`

## Performance Impact

The keep-alive options have minimal performance impact:
- **ServerAliveInterval=30**: Sends 1 small packet every 30 seconds
- **Network overhead**: ~1-2 bytes per minute
- **CPU impact**: Negligible
- **Memory impact**: None

This solution maintains connection reliability without affecting test performance or accuracy.
