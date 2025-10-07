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

# Execute Queries
echo "$(date): Creating Databases. Please make sure MySQL server 5.7 is installed"
echo "$(date): Connecting to MySQL host: $mysql_host"
mysql -h $mysql_host -u $mysql_user -p$mysql_password <"$script_dir/sqls/create-databases.sql" || { echo "Failed to create databases"; exit 1; }

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

[keystore.primary]
file_name =  "wso2carbon.jks"
type =  "JKS"
password =  "wso2carbon"
alias =  "wso2carbon"
key_password =  "wso2carbon"

[keystore.internal]
file_name =  "wso2carbon.jks"
type =  "JKS"
password =  "wso2carbon"
alias =  "wso2carbon"
key_password =  "wso2carbon"

[[apim.gateway.environment]]
name = "Production and Sandbox"
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
gateway_labels =["Production and Sandbox"]

[apim.jwt]
enable = true
encoding = "base64" # base64,base64url
#generator_impl = "org.wso2.carbon.apimgt.keymgt.token.JWTGenerator"
claim_dialect = "http://wso2.org/claims"
convert_dialect = false
header = "X-JWT-Assertion"
signing_algorithm = "RS256"
#enable_user_claims = true
#claims_extractor_impl = "org.wso2.carbon.apimgt.impl.token.ExtendedDefaultClaimsRetriever"

EOF

echo "Configuration completed for Docker deployment"
