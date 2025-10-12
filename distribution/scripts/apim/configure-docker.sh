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
# Configure WSO2 API Manager for Docker
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
mysql_host=""
mysql_user=""
mysql_password=""
mysql_connector_file=""

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -m <mysql_host> -u <mysql_user> -p <mysql_password> -c <mysql_connector_file> [-h]"
    echo ""
    echo "-m: Hostname of MySQL Server."
    echo "-u: MySQL Username."
    echo "-p: MySQL Password."
    echo "-c: JAR file of the MySQL Connector"
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "m:u:p:c:h" opt; do
    case "${opt}" in
    m)
        mysql_host=${OPTARG}
        ;;
    u)
        mysql_user=${OPTARG}
        ;;
    p)
        mysql_password=${OPTARG}
        ;;
    c)
        mysql_connector_file=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"

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
if [[ ! -f $mysql_connector_file ]]; then
    echo "Please provide the MySQL connector file."
    exit 1
fi

validate_command() {
    # Check whether given command exists
    if ! command -v $1 >/dev/null 2>&1; then
        echo "Please Install $2"
        exit 1
    fi
}

replace_value() {
    echo "Replacing $2 with $3"
    find $1 -type f -exec sed -i -e "s/$2/$3/g" {} \;
}

validate_command mysql mysql-client

if [[ ! -f $mysql_connector_file ]]; then
    echo "Please provide the path to MySQL Connector JAR"
    exit 1
fi

# Clean up any previous database scripts
rm -f /tmp/apimgt-mysql.sql /tmp/mysql.sql

# Extract database scripts from Docker image first
echo "$(date): Extracting database scripts from WSO2 APIM Docker image..."
# Docker image should already be pulled in setup script, but ensure it exists
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "wso2/wso2am:4.5.0-rocky"; then
    echo "$(date): Docker image not found locally, pulling..."
    docker pull wso2/wso2am:4.5.0-rocky || { echo "Failed to pull WSO2 APIM Docker image"; exit 1; }
fi

echo "$(date): Available Docker images:"
docker images | grep wso2

# Create temporary container to extract database scripts
echo "$(date): Creating temporary container from wso2/wso2am:4.5.0-rocky..."
temp_container=$(docker create wso2/wso2am:4.5.0-rocky) || { echo "Failed to create temporary container"; exit 1; }
echo "$(date): Created temporary container: $temp_container"

# Extract database scripts with cleanup on failure
if ! docker cp $temp_container:/home/wso2carbon/wso2am-4.5.0/dbscripts/apimgt/mysql.sql /tmp/apimgt-mysql.sql; then
    docker rm $temp_container 2>/dev/null || true
    echo "Failed to extract APIM database script"
    exit 1
fi

if ! docker cp $temp_container:/home/wso2carbon/wso2am-4.5.0/dbscripts/mysql.sql /tmp/mysql.sql; then
    docker rm $temp_container 2>/dev/null || true
    echo "Failed to extract shared database script"
    exit 1
fi

# Clean up temporary container
docker rm $temp_container || { echo "Warning: Failed to remove temporary container"; }

# Verify database scripts were extracted
if [[ ! -f /tmp/apimgt-mysql.sql ]]; then
    echo "APIM database script not found at /tmp/apimgt-mysql.sql"
    exit 1
fi

if [[ ! -f /tmp/mysql.sql ]]; then
    echo "Shared database script not found at /tmp/mysql.sql"
    exit 1
fi

echo "$(date): Database scripts extracted successfully"
echo "$(date): APIM script size: $(wc -l < /tmp/apimgt-mysql.sql) lines"
echo "$(date): Shared script size: $(wc -l < /tmp/mysql.sql) lines"

# Create databases and initialize them step by step (avoiding the source command issue)
echo "$(date): Creating and initializing databases step by step..."

# Create and initialize apim database
echo "$(date): Creating and initializing apim database..."
mysql -h $mysql_host -u $mysql_user -p$mysql_password -e "
DROP DATABASE IF EXISTS apim;
CREATE DATABASE apim CHARACTER SET latin1;
" || { echo "Failed to create apim database"; exit 1; }

mysql -h $mysql_host -u $mysql_user -p$mysql_password apim < /tmp/apimgt-mysql.sql || { echo "Failed to initialize apim database"; exit 1; }

# Create and initialize shared database (used for registry and userstore)
echo "$(date): Creating and initializing shared database..."
mysql -h $mysql_host -u $mysql_user -p$mysql_password -e "
DROP DATABASE IF EXISTS shared;
CREATE DATABASE shared CHARACTER SET latin1;
" || { echo "Failed to create shared database"; exit 1; }

mysql -h $mysql_host -u $mysql_user -p$mysql_password shared < /tmp/mysql.sql || { echo "Failed to initialize shared database"; exit 1; }

echo "$(date): Database creation and initialization completed successfully"

# Create performance-optimized startup script (disable diagnostic tool)
echo "Creating performance-optimized API Manager startup script..."
mkdir -p wso2am-docker/bin
if [[ -f "${script_dir}/conf/api-manager-optimized.sh" ]]; then
    cp "${script_dir}/conf/api-manager-optimized.sh" wso2am-docker/bin/api-manager.sh
    chmod +x wso2am-docker/bin/api-manager.sh
    echo "Performance optimization: Diagnostic tool disabled for better performance"
else
    echo "Warning: Optimized API Manager script not found. Creating default one..."
    # Create a simple optimized script inline
    cat > wso2am-docker/bin/api-manager.sh << 'EOFSCRIPT'
#!/bin/bash
# Performance-optimized API Manager startup (diagnostic tool disabled)
CARBON_HOME="/home/wso2carbon/wso2am-4.5.0"
echo "Starting WSO2 API Manager with diagnostic tool disabled for performance"
exec "$CARBON_HOME/bin/wso2server.sh" "$@"
EOFSCRIPT
    chmod +x wso2am-docker/bin/api-manager.sh
fi

# Copy configurations after replacing values
temp_conf=$(mktemp -d /tmp/apim-conf.XXXXXX)

echo "Copying configs to a temporary directory"
cp -rv $script_dir/conf $temp_conf

replace_value $temp_conf mysql_host $mysql_host
replace_value $temp_conf mysql_user $mysql_user
replace_value $temp_conf mysql_password $mysql_password

# Copy configuration to docker directory
apim_docker_path="wso2am-docker"
if [[ -d $apim_docker_path ]]; then
    echo "$(date): Copying configuration files..."
    cp -rv $temp_conf/conf/* ${apim_docker_path}/repository/conf/ || { echo "Failed to copy configuration files"; exit 1; }
    echo "$(date): Copying MySQL connector JAR..."
    cp -v $mysql_connector_file ${apim_docker_path}/repository/components/lib/ || { echo "Failed to copy MySQL connector"; exit 1; }
    
    # Verify MySQL connector was copied
    if [[ ! -f ${apim_docker_path}/repository/components/lib/$(basename $mysql_connector_file) ]]; then
        echo "MySQL connector file not found in lib directory"
        exit 1
    fi
else
    echo "APIM Docker directory not found: $apim_docker_path"
    exit 1
fi

# Create deployment.toml for Docker
cat > ${apim_docker_path}/repository/conf/deployment.toml << EOF
[server]
hostname = "localhost"
node_ip = "127.0.0.1"
server_role = "default"

[super_admin]
username = "admin"
password = "admin"
create_admin_account = true

[user_store]
type = "database_unique_id"

[database.apim_db]
type = "mysql"
url = "jdbc:mysql://${mysql_host}:3306/apim?useSSL=false&amp;autoReconnect=true&amp;requireSSL=false&amp;verifyServerCertificate=false"
username = "${mysql_user}"
password = "${mysql_password}"
driver = "com.mysql.cj.jdbc.Driver"

[database.shared_db]
type = "mysql"
url = "jdbc:mysql://${mysql_host}:3306/shared?useSSL=false&amp;autoReconnect=true&amp;requireSSL=false&amp;verifyServerCertificate=false"
username = "${mysql_user}"
password = "${mysql_password}"
driver = "com.mysql.cj.jdbc.Driver"

[keystore.tls]
file_name =  "wso2carbon.jks"
type =  "JKS"
password =  "wso2carbon"
alias =  "wso2carbon"
key_password =  "wso2carbon"


[[apim.gateway.environment]]
name = "Default"
type = "hybrid"
provider = "wso2"
gateway_type = "Regular"
description = "This is a hybrid gateway that handles both production and sandbox token traffic."
show_as_token_endpoint_url = true
service_url = "https://localhost:9443/services/"
username= "admin"
password= "admin"
ws_endpoint = "ws://localhost:9099"
wss_endpoint = "wss://localhost:8099"
http_endpoint = "http://localhost:8280"
https_endpoint = "https://localhost:8243"

[apim.sync_runtime_artifacts.gateway]
gateway_labels =["Default"]

[apim.analytics]
enable = false
auth_token = ""

[apim.cors]
allow_origins = "*"
allow_methods = ["GET","PUT","POST","DELETE","PATCH","OPTIONS"]
allow_headers = ["authorization","Access-Control-Allow-Origin","Content-Type","SOAPAction","apikey","Internal-Key"]
allow_credentials = false

[system.parameter]
'passthrough.metrics.collection.disabled' = true

EOF

echo "Configuration completed for Docker deployment"
