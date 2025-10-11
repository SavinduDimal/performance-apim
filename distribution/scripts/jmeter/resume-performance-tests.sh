#!/bin/bash
# Script to resume interrupted performance tests
# This script can be used to restart tests if SSH timeout occurs

script_dir=$(dirname "$0")

# Execute common script
. $script_dir/perf-test-common.sh

echo "=========================================="
echo "Performance Test Resume Script"
echo "=========================================="
echo "This script attempts to resume interrupted performance tests."
echo "It will check for completed scenarios and continue from where it left off."
echo ""

# Check for existing results to determine which scenarios have completed
results_dir="${HOME}/results"
if [[ ! -d "$results_dir" ]]; then
    echo "No results directory found. Starting fresh test run..."
    exec $script_dir/run-performance-tests.sh "$@"
fi

echo "Found existing results directory. Checking for completed scenarios..."

# Create a list of completed scenarios by checking for result files
completed_scenarios=()
for result_file in ${results_dir}/*.jtl; do
    if [[ -f "$result_file" ]]; then
        scenario_name=$(basename "$result_file" .jtl)
        echo "Found completed scenario: $scenario_name"
        completed_scenarios+=("$scenario_name")
    fi
done

if [[ ${#completed_scenarios[@]} -eq 0 ]]; then
    echo "No completed scenarios found. Starting fresh test run..."
    exec $script_dir/run-performance-tests.sh "$@"
fi

echo ""
echo "Completed scenarios: ${#completed_scenarios[@]}"
echo "Resuming tests to complete remaining scenarios..."
echo ""

# Set environment variable to indicate this is a resume operation
export RESUME_TESTS=true
export COMPLETED_SCENARIOS="${completed_scenarios[*]}"

# Execute the main test script
exec $script_dir/run-performance-tests.sh "$@"
