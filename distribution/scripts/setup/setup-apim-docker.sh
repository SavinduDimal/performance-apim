#!/bin/bash -e
# Copyright 2025 WSO2 LLC. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------------------------------------------------------------------------
# Setup WSO2 API Manager using Docker
# ----------------------------------------------------------------------------

# This script will configure and setup WSO2 API Manager using Docker containers

# Make sure the script is running as root.
if [ "$UID" -ne "0" ]; then
    echo "You must be root to run $0. Try following"
    echo "sudo $0"
    exit 9
fi

export script_name="$0"
export script_dir=$(dirname "$0")
export netty_host=""
export mysql_host=""
export mysql_user=""
export mysql_password=""
export mysql_connector_file=""
export apim_docker_image=""
export oracle_jdk_dist=""
export os_user=""
export token_type="JWT"
export apim_heap_size="2G"

function usageCommand() {
    echo "-j <oracle_jdk_dist> -i <apim_docker_image> -c <mysql_connector_file> -n <netty_host> -m <mysql_host> -u <mysql_username> -p <mysql_password> -o <os_user> -t <token_type> -s <heap_size>"
}
export -f usageCommand

function usageHelp() {
    echo "-j: Oracle JDK distribution."
    echo "-i: WSO2 API Manager Docker Image (e.g., wso2/wso2am:4.5.0-rocky)."
    echo "-c: MySQL Connector JAR file."
    echo "-n: The hostname of Netty service."
    echo "-m: The hostname of MySQL service."
    echo "-u: MySQL Username."
    echo "-p: MySQL Password."
    echo "-o: General user of the OS."
    echo "-t: Token type. Either JWT or OAUTH. Default is JWT."
    echo "-s: Heap size for APIM. Default is 2G."
}
export -f usageHelp

while getopts "gp:w:o:hj:i:c:n:m:u:p:o:t:s:" opt; do
    case "${opt}" in
    j)
        oracle_jdk_dist=${OPTARG}
        ;;
    i)
        apim_docker_image=${OPTARG}
        ;;
    c)
        mysql_connector_file=${OPTARG}
        ;;
    n)
        netty_host=${OPTARG}
        ;;
    m)
        mysql_host=${OPTARG}
        ;;
    u)
        mysql_user=${OPTARG}
        ;;
    p)
        mysql_password=${OPTARG}
        ;;
    o)
        os_user=${OPTARG}
        ;;
    t)
        token_type=${OPTARG}
        ;;
    s)
        apim_heap_size=${OPTARG}
        ;;
    *)
        opts+=("-${opt}")
        [[ -n "$OPTARG" ]] && opts+=("$OPTARG")
        ;;
    esac
done
shift "$((OPTIND - 1))"

function validate() {
    if [[ ! -f $oracle_jdk_dist ]]; then
        echo "Please download Oracle JDK."
        exit 1
    fi
    if [[ -z $apim_docker_image ]]; then
        echo "Please provide the apim_docker_image."
        exit 1
    fi
    if [[ ! -f $mysql_connector_file ]]; then
        echo "Please provide the MySQL connector file."
        exit 1
    fi
    if [[ -z $netty_host ]]; then
        echo "Please provide the hostname of Netty Service."
        exit 1
    fi
    if [[ -z $mysql_host ]]; then
        echo "Please provide the hostname of MySQL host."
        exit 1
    fi
    if [[ -z $mysql_user ]]; then
        echo "Please provide the MySQL username."
        exit 1
    fi
    if [[ -z $mysql_password ]]; then
        echo "Please provide the MySQL password."
        exit 1
    fi
    if [[ -z $os_user ]]; then
        echo "Please provide the username of the general os user"
        exit 1
    fi

}
export -f validate

function mediation_out_sequence() {
    cat <<EOF
<sequence xmlns=\"http://ws.apache.org/ns/synapse\" name=\"mediation-api-sequence\">
    <payloadFactory media-type=\"json\">
        <format>
            {\"payload\":\"\$1\",\"size\":\"\$2\"}
        </format>
        <args>
            <arg expression=\"\$.payload\" evaluator=\"json\"></arg>
            <arg expression=\"\$.size\" evaluator=\"json\"></arg>
        </args>
    </payloadFactory>
</sequence>
EOF
}
export -f mediation_out_sequence

function setup() {
    install_dir=/home/$os_user
    $script_dir/../java/install-java.sh -f $oracle_jdk_dist -u $os_user

    pushd ${install_dir}

    # Install Docker if not already installed
    $script_dir/../../performance-common/distribution/scripts/docker/install-docker.sh -u $os_user

    # Create directory structure for APIM Docker setup
    sudo -u $os_user mkdir -p wso2am-docker/{conf,logs,repository/database/drivers}
    
    # Copy MySQL connector
    sudo -u $os_user cp $mysql_connector_file wso2am-docker/repository/database/drivers/

    # Create APIM configuration for Docker (reuse existing configure.sh logic)
    sudo -u $os_user $script_dir/../apim/configure.sh -m $mysql_host -u $mysql_user -p $mysql_password -c $mysql_connector_file

    # Start APIM using Docker instead of traditional way
    sudo -u $os_user $script_dir/../apim/apim-docker-start.sh -i $apim_docker_image -m $apim_heap_size

    # Create APIs in Local API Manager (same as original)
    sudo -u $os_user $script_dir/../apim/create-api.sh -a localhost -n "echo" -d "Echo API" -b "http://${netty_host}:8688/" -k $token_type
    sudo -u $os_user $script_dir/../apim/create-api.sh -a localhost -n "mediation" -d "Mediation API" -b "http://${netty_host}:8688/" \
        -o "$(mediation_out_sequence | tr -d "\n\r")" -k $token_type

    if [ "$token_type" == "JWT" ]; then
        tokens_csv="$script_dir/../apim/target/tokens.csv"
        if [[ -f $tokens_csv ]]; then
            sudo -u $os_user rm -f $tokens_csv
        fi
        sudo -u $os_user $script_dir/../apim/generate-jwt-tokens.sh -t 4000
    else
        # Generate tokens
        tokens_sql="$script_dir/../apim/target/tokens.sql"
        if [[ ! -f $tokens_sql ]]; then
            sudo -u $os_user $script_dir/../apim/generate-tokens.sh -t 4000
        fi

        if [[ -f $tokens_sql ]]; then
            mysql -h $mysql_host -u $mysql_user -p$mysql_password apim <$tokens_sql
        else
            echo "SQL file with generated tokens not found."
            exit 1
        fi
    fi

    popd
    echo "Completed Docker-based API Manager setup..."
}
export -f setup

$script_dir/setup-common.sh "${opts[@]}" "$@" -p curl -p jq -p mysql-client
