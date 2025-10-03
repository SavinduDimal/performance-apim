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
# Run performance tests on AWS Cloudformation Stacks with Docker-based APIM
# ----------------------------------------------------------------------------

export script_name="$0"
export script_dir=$(dirname "$0")

export apim_docker_image=""
export jdk11_distribution=""
export mysql_connector_jar=""
export wso2am_ec2_instance_type=""
export wso2am_rds_db_instance_class=""

export aws_cloudformation_template_filename="apim_docker_perf_test_cfn.yaml"
export application_name="WSO2 API Manager (Docker)"
export ec2_instance_name="wso2am-docker"
export metrics_file_prefix="apim-docker"
export run_performance_tests_script_name="run-docker-performance-tests.sh"

function usageCommand() {
    echo "-i <apim_docker_image> -c <mysql_connector_jar> -A <wso2am_ec2_instance_type> -D <wso2am_rds_db_instance_class> -q <jdk11_distribution>"
}
export -f usageCommand

function usageHelp() {
    echo "-i: WSO2 API Manager Docker Image (e.g., wso2/wso2am:4.5.0-rocky)."
    echo "-c: MySQL Connector JAR file."
    echo "-A: Amazon EC2 Instance Type for WSO2 API Manager."
    echo "-D: Amazon EC2 DB Instance Class for WSO2 API Manager RDS Instance."
    echo "-q: JDK 11 Distribution."
    echo ""
    echo "Performance Test Parameters (same as original):"
    echo "-m: Application heap memory sizes. Multiple options allowed. Suffixes: M, G."
    echo "-u: Concurrent Users to test. Multiple options allowed."
    echo "-b: Message sizes in bytes. Multiple options allowed."
    echo "-s: Backend Sleep Times in milliseconds. Multiple options allowed."
    echo "-d: Test Duration in seconds. Default 900."
    echo "-w: Warm-up time in seconds. Default 300."
    echo "-j: Heap Size of JMeter Server. Suffixes: M, G. Default 4G."
    echo "-k: Heap Size of JMeter Client. Suffixes: M, G. Default 2G."
    echo "-l: Heap Size of Netty Service. Suffixes: M, G. Default 4G."
    echo "-i: Scenario name to be included. Multiple options allowed."
    echo "-e: Scenario name to be excluded. Multiple options allowed."
}
export -f usageHelp

while getopts ":u:f:d:k:n:j:o:g:s:b:r:J:S:N:t:p:w:hi:c:A:D:q:" opt; do
    case "${opt}" in
    i)
        apim_docker_image=${OPTARG}
        ;;
    c)
        mysql_connector_jar=${OPTARG}
        ;;
    A)
        wso2am_ec2_instance_type=${OPTARG}
        ;;
    D)
        wso2am_rds_db_instance_class=${OPTARG}
        ;;
    q)
        jdk11_distribution=${OPTARG}
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

    # Validate Docker image format
    if [[ ! $apim_docker_image =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
        echo "Invalid Docker image format. Expected format: registry/image:tag"
        exit 1
    fi

    export apim_docker_image_name="$apim_docker_image"

    if [[ ! -f $jdk11_distribution ]]; then
        echo "Please provide jdk11 distribution."
        exit 1
    fi
    export jdk11_distribution_filename=$(basename $jdk11_distribution)

    if [[ ! -f $mysql_connector_jar ]]; then
        echo "Please provide MySQL Connector JAR file."
        exit 1
    fi

    export mysql_connector_jar_filename=$(basename $mysql_connector_jar)

    if [[ ${mysql_connector_jar_filename: -4} != ".jar" ]]; then
        echo "MySQL Connector JAR must have .jar extension"
        exit 1
    fi

    if [[ -z $wso2am_ec2_instance_type ]]; then
        echo "Please provide the Amazon EC2 Instance Type for WSO2 API Manager."
        exit 1
    fi

    if [[ -z $wso2am_rds_db_instance_class ]]; then
        echo "Please provide the Amazon EC2 DB Instance Class for WSO2 API Manager RDS Instance."
        exit 1
    fi
}
export -f validate

function create_links() {
    jdk11_distribution=$(realpath $jdk11_distribution)
    mysql_connector_jar=$(realpath $mysql_connector_jar)
    ln -s $jdk11_distribution $temp_dir/$jdk11_distribution_filename
    ln -s $mysql_connector_jar $temp_dir/$mysql_connector_jar_filename
}
export -f create_links

function get_test_metadata() {
    echo "application_name=$application_name"
    echo "apim_docker_image=$apim_docker_image_name"
    echo "wso2am_ec2_instance_type=$wso2am_ec2_instance_type"
    echo "wso2am_rds_db_instance_class=$wso2am_rds_db_instance_class"
}
export -f get_test_metadata

function get_cf_parameters() {
    echo "APIManagerDockerImage=$apim_docker_image_name"
    echo "JDK11DistributionName=$jdk11_distribution_filename"
    echo "MySQLConnectorJarName=$mysql_connector_jar_filename"
    echo "WSO2APIManagerInstanceType=$wso2am_ec2_instance_type"
    echo "WSO2APIManagerDBInstanceClass=$wso2am_rds_db_instance_class"
    echo "MasterUsername=wso2carbon"
    echo "MasterUserPassword=wso2carbon#9762"
}
export -f get_cf_parameters

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
export -f get_columns

$script_dir/cloudformation-common.sh "${opts[@]}" -- "$@"
