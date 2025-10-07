#!/bin/bash -e
# Copyright 2017 WSO2 Inc. (http://wso2.org)
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

# This script will run all other scripts to configure and setup WSO2 API Manager using Docker

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
export docker_image=""
export os_user=""
export token_type="JWT"

function usageCommand() {
    echo "-i <docker_image> -c <mysql_connector_file> -n <netty_host> -m <mysql_host> -u <mysql_username> -p <mysql_password> -o <os_user> -t <token_type>"
}
export -f usageCommand

function usageHelp() {
    echo "-i: WSO2 API Manager Docker image."
    echo "-c: MySQL Connector JAR file."
    echo "-n: The hostname of Netty service."
    echo "-m: The hostname of MySQL service."
    echo "-u: MySQL Username."
    echo "-p: MySQL Password."
    echo "-o: General user of the OS."
    echo "-t: Token type. Either JWT or OAUTH. Default is JWT."
}
export -f usageHelp

while getopts "gp:w:o:hi:c:n:m:u:p:o:t:" opt; do
    case "${opt}" in
    i)
        docker_image=${OPTARG}
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
    *)
        opts+=("-${opt}")
        [[ -n "$OPTARG" ]] && opts+=("$OPTARG")
        ;;
    esac
done
shift "$((OPTIND - 1))"

function validate() {
    if [[ -z $docker_image ]]; then
        echo "Please provide the Docker image for WSO2 API Manager."
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

    # Install Docker
    echo "$(date): Starting Docker installation..."
    
    # Update package list
    apt-get update || { echo "Failed to update package list"; exit 1; }
    
    # Install prerequisites
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release || { echo "Failed to install prerequisites"; exit 1; }
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo "Failed to add Docker GPG key"; exit 1; }
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package list with Docker repository
    apt-get update || { echo "Failed to update package list after adding Docker repo"; exit 1; }
    
    # Install Docker
    apt-get install -y docker-ce docker-ce-cli containerd.io || { echo "Failed to install Docker"; exit 1; }
    
    # Add user to docker group
    usermod -aG docker $os_user
    
    # Start Docker service
    systemctl start docker || { echo "Failed to start Docker service"; exit 1; }
    systemctl enable docker || { echo "Failed to enable Docker service"; exit 1; }
    
    # Wait for Docker to be ready
    echo "$(date): Waiting for Docker to be ready..."
    sleep 10
    
    # Test Docker installation
    docker --version || { echo "Docker installation verification failed"; exit 1; }
    
    # Install Docker Compose
    echo "$(date): Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Failed to download Docker Compose"; exit 1; }
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Test Docker Compose installation
    docker-compose --version || { echo "Docker Compose installation verification failed"; exit 1; }

    # Pull WSO2 APIM Docker image early for database initialization
    echo "$(date): Pre-pulling WSO2 APIM Docker image..."
    docker pull wso2/wso2am:4.5.0-rocky || { echo "Failed to pull WSO2 APIM Docker image"; exit 1; }

    pushd ${install_dir}

    # Create directories for APIM configuration
    echo "$(date): Creating APIM configuration directories..."
    sudo -u $os_user mkdir -p wso2am-docker/repository/conf || { echo "Failed to create conf directory"; exit 1; }
    sudo -u $os_user mkdir -p wso2am-docker/repository/components/lib || { echo "Failed to create lib directory"; exit 1; }
    sudo -u $os_user mkdir -p wso2am-docker/repository/deployment/server/synapse-configs/default/sequences || { echo "Failed to create sequences directory"; exit 1; }

    # Wait for MySQL to be ready
    echo "$(date): Waiting for MySQL database to be ready..."
    for i in {1..30}; do
        if mysql -h $mysql_host -u $mysql_user -p$mysql_password -e "SELECT 1;" >/dev/null 2>&1; then
            echo "$(date): MySQL database is ready"
            break
        fi
        echo "$(date): Waiting for MySQL... (attempt $i/30)"
        sleep 10
    done

    # Configure WSO2 API Manager
    echo "$(date): Configuring WSO2 API Manager..."
    sudo -u $os_user $script_dir/../apim/configure-docker.sh -m $mysql_host -u $mysql_user -p $mysql_password -c $mysql_connector_file || { echo "Failed to configure APIM"; exit 1; }

    # Start API Manager using Docker (test first with minimal config)
    echo "$(date): Testing WSO2 API Manager Docker container startup..."
    sudo -u $os_user $script_dir/../apim/apim-start-docker-test.sh -i $docker_image -m 2G || { 
        echo "Basic Docker container test failed, trying with full configuration..."
        sudo -u $os_user $script_dir/../apim/apim-start-docker-simple.sh -i $docker_image -m 2G || { 
            echo "Failed to start APIM Docker container"; 
            exit 1; 
        }
    }

    # Wait for APIM to start
    echo "Waiting for API Manager to start"
    exit_status=100
    n=0
    until [ $n -ge 60 ]; do
        response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "")"
        if [ $response_code -eq 200 ]; then
            echo "API Manager started"
            exit_status=0
            break
        fi
        sleep 10
        n=$(($n + 1))
    done

    if [ $exit_status -ne 0 ]; then
        echo "API Manager failed to start"
        exit 1
    fi

    # Create APIs in Local API Manager
    sudo -u $os_user $script_dir/../apim/create-api.sh -a localhost -n "echo" -d "Echo API" -b "http://${netty_host}:8688/" -k $token_type
    sudo -u $os_user $script_dir/../apim/create-api.sh -a localhost -n "mediation" -d "Mediation API" -b "http://${netty_host}:8688/" \
        -o "$(mediation_out_sequence | tr -d "\n\r")" -k $token_type

    if [ "$token_type" == "JWT" ]; then
        tokens_csv="$script_dir/../apim/target/tokens.csv"
        if [[ -f $tokens_csv ]]; then
            sudo -u $os_user rm $tokens_csv
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
    echo "Completed API Manager Docker setup..."
}
export -f setup

# Log all output to a file for debugging
exec 1> >(tee -a /var/log/apim-docker-setup.log)
exec 2> >(tee -a /var/log/apim-docker-setup.log >&2)

echo "$(date): Starting APIM Docker setup with parameters:"
echo "  Docker image: $docker_image"
echo "  MySQL host: $mysql_host"
echo "  MySQL user: $mysql_user"
echo "  Netty host: $netty_host"
echo "  OS user: $os_user"
echo "  Token type: $token_type"

$script_dir/setup-common.sh "${opts[@]}" "$@" -p curl -p jq -p mysql-client
