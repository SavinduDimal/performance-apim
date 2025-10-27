#!/bin/bash -e
# Copyright (c) 2018, WSO2 Inc. (http://wso2.org) All Rights Reserved.
#
# WSO2 Inc. licenses this file to you under the Apache License,
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
# Run performance tests on AWS Cloudformation Stacks
# ----------------------------------------------------------------------------

export script_name="$0"
export script_dir=$(dirname "$0")

export wso2am_distribution=""
export jdk11_distribution=""
export mysql_connector_jar=""
export wso2am_ec2_instance_type=""
export wso2am_rds_db_instance_class=""
export docker_image="wso2/wso2am:4.5.0-alpine"

export aws_cloudformation_template_filename="apim_perf_test_cfn.yaml"
export application_name="WSO2 API Manager"
export ec2_instance_name="wso2am"
export metrics_file_prefix="apim"
export run_performance_tests_script_name="run-performance-tests.sh"

function usageCommand() {
    echo "-c <mysql_connector_jar> -A <wso2am_ec2_instance_type> -D <wso2am_rds_db_instance_class> [-a <wso2am_distribution>] [-q <jdk11_distribution>]"
}
export -f usageCommand

function usageHelp() {
    echo "-c: MySQL Connector JAR file."
    echo "-A: Amazon EC2 Instance Type for WSO2 API Manager."
    echo "-D: Amazon EC2 DB Instance Class for WSO2 API Manager RDS Instance."
    echo "-a: WSO2 API Manager Distribution (legacy parameter, will be ignored - Docker image wso2/wso2am:4.5.0-alpine will be used)."
    echo "-q: JDK 11 Distribution (legacy parameter, will be ignored - Docker image includes JDK)."

}
export -f usageHelp

while getopts ":u:f:d:k:n:j:o:g:s:b:r:J:S:N:t:p:w:ha:c:A:D:q:" opt; do
    case "${opt}" in
    a)
        wso2am_distribution=${OPTARG}
        echo "Note: WSO2 APIM zip file parameter detected but will be ignored. Using Docker image: $docker_image"
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
        echo "Note: JDK 11 distribution parameter detected but will be ignored. Using Docker image: $docker_image"
        ;;
    *)
        opts+=("-${opt}")
        [[ -n "$OPTARG" ]] && opts+=("$OPTARG")
        ;;
    esac
done
shift "$((OPTIND - 1))"

function validate() {
    # Handle backward compatibility - if APIM distribution is provided, show note but continue with Docker
    if [[ -n $wso2am_distribution ]]; then
        echo "Note: WSO2 APIM distribution file provided but Docker deployment will be used instead"
        export wso2am_distribution_filename=$(basename $wso2am_distribution)
    fi
    
    # Handle backward compatibility - if JDK distribution is provided, show note but continue with Docker
    if [[ -n $jdk11_distribution ]]; then
        echo "Note: JDK 11 distribution file provided but Docker deployment will be used instead"
        export jdk11_distribution_filename=$(basename $jdk11_distribution)
    fi

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
    mysql_connector_jar=$(realpath $mysql_connector_jar)
    ln -s $mysql_connector_jar $temp_dir/$mysql_connector_jar_filename
    
    # Handle backward compatibility - create symbolic links if legacy files are provided
    if [[ -n $wso2am_distribution && -f $wso2am_distribution ]]; then
        wso2am_distribution=$(realpath $wso2am_distribution)
        ln -s $wso2am_distribution $temp_dir/$wso2am_distribution_filename
    fi
    
    if [[ -n $jdk11_distribution && -f $jdk11_distribution ]]; then
        jdk11_distribution=$(realpath $jdk11_distribution)  
        ln -s $jdk11_distribution $temp_dir/$jdk11_distribution_filename
    fi
}
export -f create_links

function get_test_metadata() {
    echo "application_name=$application_name"
    echo "wso2am_ec2_instance_type=$wso2am_ec2_instance_type"
    echo "wso2am_rds_db_instance_class=$wso2am_rds_db_instance_class"
}
export -f get_test_metadata

function get_cf_parameters() {
    echo "WSO2APIManagerDockerImage=$docker_image"
    echo "MySQLConnectorJarName=$mysql_connector_jar_filename"
    echo "WSO2APIManagerInstanceType=$wso2am_ec2_instance_type"
    echo "WSO2APIManagerDBInstanceClass=$wso2am_rds_db_instance_class"
    echo "MasterUsername=wso2carbon"
    echo "MasterUserPassword=wso2carbon#9762"
    
    # Include legacy parameters if they exist (for backward compatibility with templates)
    if [[ -n $wso2am_distribution_filename ]]; then
        echo "WSO2APIManagerDistributionName=$wso2am_distribution_filename"
    fi
    
    if [[ -n $jdk11_distribution_filename ]]; then
        echo "JDK11DistributionName=$jdk11_distribution_filename"
    fi
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
