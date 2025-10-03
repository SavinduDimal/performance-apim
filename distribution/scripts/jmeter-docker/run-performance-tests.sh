#!/bin/bash -e
# Copyright 2025 WSO2 LLC. (http://wso2.com) All Rights Reserved.
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# ----------------------------------------------------------------------------
# Run JMeter performance tests with Docker containers
# ----------------------------------------------------------------------------

export script_name="$0"
export script_dir=$(dirname "$0")

export apim_host="localhost"
export apim_port="8243"
export jmeter_docker_image="justb4/jmeter:5.3"

function usageCommand() {
    echo "-a <apim_host> -p <apim_port> -j <jmeter_docker_image>"
}

function usageHelp() {
    echo "-a: WSO2 API Manager host."
    echo "-p: WSO2 API Manager HTTPS port."
    echo "-j: JMeter Docker Image."
}

while getopts ":u:f:d:k:n:o:g:s:b:r:t:p:w:ha:p:j:" opt; do
    case "${opt}" in
    a)
        apim_host=${OPTARG}
        ;;
    p)
        apim_port=${OPTARG}
        ;;
    j)  
        jmeter_docker_image=${OPTARG}
        ;;
    *)
        opts+=("-${opt}")
        [[ -n "$OPTARG" ]] && opts+=("$OPTARG")
        ;;
    esac
done
shift "$((OPTIND - 1))"

function validate() {
    if [[ -z $apim_host ]]; then
        echo "Please provide WSO2 API Manager host."
        exit 1
    fi
    
    if [[ -z $apim_port ]]; then
        echo "Please provide WSO2 API Manager port."
        exit 1
    fi
}

function run_jmeter_test() {
    local test_name="$1"
    local jmx_file="$2"
    local additional_params="$3"
    
    echo "Running JMeter test: $test_name"
    
    # Create results directory if it doesn't exist
    mkdir -p results
    
    # Run JMeter in Docker container
    docker run --rm \
        --network apim-network \
        -v $(pwd)/jmeter:/tests \
        -v $(pwd)/results:/results \
        $jmeter_docker_image \
        -n -t /tests/$jmx_file \
        -l /results/${test_name}_results.jtl \
        -e -o /results/${test_name}_report \
        -Japim.host=$apim_host \
        -Japim.port=$apim_port \
        $additional_params
        
    echo "JMeter test completed: $test_name"
    echo "Results saved to: results/${test_name}_results.jtl"
    echo "Report saved to: results/${test_name}_report"
}

function create_links() {
    # No need to create links for Docker-based setup
    echo "Docker-based JMeter testing - no file links required"
}

function get_test_metadata() {
    echo "jmeter_mode=docker"
    echo "apim_host=$apim_host"
    echo "apim_port=$apim_port"
    echo "jmeter_docker_image=$jmeter_docker_image"
}

# Set up environment
export application_name="WSO2 API Manager JMeter Tests (Docker)"
export metrics_file_prefix="jmeter-docker"

# Export functions for use by other scripts
export -f usageCommand
export -f usageHelp
export -f validate
export -f create_links
export -f get_test_metadata
export -f run_jmeter_test

# Source the common performance testing infrastructure if it exists
if [ -f "$script_dir/jmeter-common.sh" ]; then
    $script_dir/jmeter-common.sh "${opts[@]}" -- "$@"
else
    echo "JMeter Docker setup completed. Use run_jmeter_test function to execute tests."
fi
