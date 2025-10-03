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
# Run performance tests for Docker-based WSO2 API Manager deployment
# ----------------------------------------------------------------------------

export script_name="$0"
export script_dir=$(dirname "$0")

export apim_docker_image="wso2/wso2am:4.5.0-rocky"
export jmeter_docker_image="justb4/jmeter:5.3"

function usageCommand() {
    echo "-i <apim_docker_image> -j <jmeter_docker_image>"
}

function usageHelp() {
    echo "-i: WSO2 API Manager Docker Image."
    echo "-j: JMeter Docker Image."
}

while getopts ":u:f:d:k:n:o:g:s:b:r:t:p:w:hi:j:" opt; do
    case "${opt}" in
    i)
        apim_docker_image=${OPTARG}
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
    if [[ -z $apim_docker_image ]]; then
        echo "Please provide WSO2 API Manager Docker Image."
        exit 1
    fi
}

function create_links() {
    # No need to create links for Docker images
    echo "Using Docker images - no file links required"
}

function get_test_metadata() {
    echo "application_name=WSO2 API Manager (Docker)"
    echo "apim_docker_image=$apim_docker_image"
    echo "jmeter_docker_image=$jmeter_docker_image"
}

function get_cf_parameters() {
    echo "APIManagerDockerImage=$apim_docker_image"
    echo "JMeterDockerImage=$jmeter_docker_image"
}

function get_columns() {
    echo "Scenario Name"
    echo "Heap Size"
    echo "Concurrent Users"
    echo "Message Size (Bytes)"
    echo "Back-end Service Delay (ms)"
    echo "Error %"
    echo "Throughput (Requests/sec)"
    echo "Average Response Time (ms)"
    echo "Standard Deviation of Response Time (ms)"
    echo "99th Percentile of Response Time (ms)"
    echo "WSO2 API Manager GC Throughput (%)"
    echo "Average WSO2 API Manager Memory Footprint After Full GC (M)"
}

# Set up environment
export aws_cloudformation_template_filename="apim_docker_perf_test_cfn.yaml"
export application_name="WSO2 API Manager (Docker)"
export ec2_instance_name="wso2am-docker"
export metrics_file_prefix="apim-docker"
export run_performance_tests_script_name="run-docker-performance-tests.sh"

# Export functions for use by other scripts
export -f usageCommand
export -f usageHelp
export -f validate
export -f create_links
export -f get_test_metadata
export -f get_cf_parameters
export -f get_columns

# Source the common performance testing infrastructure
$script_dir/cloudformation-common.sh "${opts[@]}" -- "$@"
