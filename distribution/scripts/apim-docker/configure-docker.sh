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
# Configure WSO2 API Manager for Docker deployment
# ----------------------------------------------------------------------------

export mysql_host=""
export mysql_user=""
export mysql_password=""
export mysql_connector_file=""

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -m <mysql_host> -u <mysql_user> -p <mysql_password> -c <mysql_connector_file>"
    echo "-m: MySQL Host."
    echo "-u: MySQL Username."
    echo "-p: MySQL Password."
    echo "-c: MySQL Connector JAR file."
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

if [[ -z $mysql_host || -z $mysql_user || -z $mysql_password || -z $mysql_connector_file ]]; then
    echo "All parameters are required."
    usage
    exit 1
fi

# Create configuration directory
mkdir -p wso2am-docker/conf/datasources

# Create deployment.toml for Docker container
cat > wso2am-docker/conf/deployment.toml << EOF
[server]
hostname = "localhost"
node_ip = "127.0.0.1"
server_role = "default"

[user_store]
type = "database_unique_id"

[super_admin]
username = "admin"
password = "admin"
create_admin_account = true

[database.apim_db]
type = "mysql"
hostname = "$mysql_host"
name = "WSO2AM_DB"
username = "$mysql_user"
password = "$mysql_password"
driver = "com.mysql.cj.jdbc.Driver"
url = "jdbc:mysql://$mysql_host:3306/WSO2AM_DB?useSSL=false&amp;autoReconnect=true&amp;requireSSL=false&amp;verifyServerCertificate=false"

[database.shared_db]
type = "mysql"
hostname = "$mysql_host"
name = "WSO2AM_DB"
username = "$mysql_user"
password = "$mysql_password"
driver = "com.mysql.cj.jdbc.Driver"
url = "jdbc:mysql://$mysql_host:3306/WSO2AM_DB?useSSL=false&amp;autoReconnect=true&amp;requireSSL=false&amp;verifyServerCertificate=false"

[keystore.tls]
file_name = "wso2carbon.jks"
type = "JKS"
password = "wso2carbon"
alias = "wso2carbon"
key_password = "wso2carbon"

[keystore.primary]
file_name = "wso2carbon.jks"
type = "JKS"
password = "wso2carbon"
alias = "wso2carbon"
key_password = "wso2carbon"

[keystore.internal]
file_name = "wso2carbon.jks"
type = "JKS"
password = "wso2carbon"
alias = "wso2carbon"
key_password = "wso2carbon"

[[apim.gateway.environment]]
name = "Default"
type = "hybrid"
display_in_api_console = true
description = "This is a hybrid gateway that handles both production and sandbox token traffic."
show_as_token_endpoint_url = true
service_url = "https://localhost:9443/services/"
username = "admin"
password = "admin"
ws_endpoint = "ws://localhost:9099"
wss_endpoint = "wss://localhost:8099"
http_endpoint = "http://localhost:8280"
https_endpoint = "https://localhost:8243"

[apim.analytics]
enable = false

[apim.key_manager]
service_url = "https://localhost:9443/services/"
username = "admin"
password = "admin"

[apim.oauth_config]
enable_outbound_auth_header = false
auth_header = "Authorization"
revoke_endpoint = "https://localhost:8243/revoke"
enable_token_encryption = false
enable_token_hashing = false

[apim.devportal]
url = "https://localhost:9443/devportal"
enable_application_sharing = false
if_application_sharing_type = "default"
display_multiple_versions = false
display_deprecated_apis = false
enable_comments = true
enable_ratings = true
enable_forum = true

[transport.http]
properties.port = 8280
properties.proxyPort = 80

[transport.https]
properties.port = 8243
properties.proxyPort = 443

[apim.cors]
allow_origins = "*"
allow_methods = ["GET","PUT","POST","DELETE","PATCH","OPTIONS"]
allow_headers = ["authorization","Access-Control-Allow-Origin","Content-Type","SOAPAction"]
allow_credentials = false

EOF

echo "Docker configuration created successfully."
echo "Configuration saved to: wso2am-docker/conf/deployment.toml"

# Copy the MySQL connector to the appropriate location
if [[ -f $mysql_connector_file ]]; then
    cp $mysql_connector_file wso2am-docker/repository/database/drivers/
    echo "MySQL connector copied to wso2am-docker/repository/database/drivers/"
fi
