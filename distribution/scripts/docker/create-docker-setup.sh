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
# Create Docker setup for WSO2 API Manager Performance Testing
# ----------------------------------------------------------------------------

export apim_docker_image="wso2/wso2am:4.5.0-rocky"
export mysql_docker_image="mysql:8.0"
export docker_compose_file="docker-compose-perf.yml"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 [-i <apim_docker_image>] [-d <mysql_docker_image>] [-f <docker_compose_file>] [-h]"
    echo "-i: WSO2 API Manager Docker Image. Default: $apim_docker_image."
    echo "-d: MySQL Docker Image. Default: $mysql_docker_image."
    echo "-f: Docker Compose file name. Default: $docker_compose_file."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "i:d:f:h" opt; do
    case "${opt}" in
    i)
        apim_docker_image=${OPTARG}
        ;;
    d)
        mysql_docker_image=${OPTARG}
        ;;
    f)
        docker_compose_file=${OPTARG}
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

echo "Creating Docker setup for WSO2 API Manager Performance Testing..."
echo "APIM Docker Image: $apim_docker_image"
echo "MySQL Docker Image: $mysql_docker_image"
echo "Docker Compose File: $docker_compose_file"

# Create Docker Compose file for the setup
cat > $docker_compose_file << EOF
version: '3.8'

services:
  wso2am-mysql:
    image: $mysql_docker_image
    container_name: wso2am-mysql
    hostname: wso2am-mysql
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: wso2carbon#9762
      MYSQL_DATABASE: WSO2AM_DB
      MYSQL_USER: wso2carbon
      MYSQL_PASSWORD: wso2carbon#9762
    command: --max_connections=200 --innodb_buffer_pool_size=1G --innodb_log_file_size=256M
    volumes:
      - mysql_data:/var/lib/mysql
      - ./mysql-init:/docker-entrypoint-initdb.d
    networks:
      - apim-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-pwso2carbon#9762"]
      timeout: 20s
      retries: 10

  wso2am:
    image: $apim_docker_image
    container_name: wso2am-instance
    hostname: wso2am
    ports:
      - "8280:8280"
      - "8243:8243"
      - "9443:9443"
      - "9999:9999"
      - "11111:11111"
    environment:
      JAVA_OPTS: "-Xms2G -Xmx2G -Xlog:gc*,safepoint,gc+heap=trace:/home/wso2carbon/wso2am-4.5.0/repository/logs/gc.log:uptime,utctime,level,tags"
    volumes:
      - ./wso2am-docker/conf:/home/wso2carbon/wso2am-4.5.0/repository/conf
      - ./wso2am-docker/logs:/home/wso2carbon/wso2am-4.5.0/repository/logs
      - ./wso2am-docker/repository/database/drivers:/home/wso2carbon/wso2am-4.5.0/repository/components/lib
    depends_on:
      wso2am-mysql:
        condition: service_healthy
    networks:
      - apim-network
    healthcheck:
      test: ["CMD", "curl", "-f", "https://localhost:8243/services/Version"]
      timeout: 20s
      retries: 10

networks:
  apim-network:
    driver: bridge

volumes:
  mysql_data:

EOF

# Create MySQL initialization script
mkdir -p mysql-init

cat > mysql-init/01-init-db.sql << EOF
-- Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
--
-- WSO2 Inc. licenses this file to you under the Apache License,
-- Version 2.0 (the "License"); you may not use this file except
-- in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations
-- under the License.

-- Initialize WSO2AM_DB database
CREATE DATABASE IF NOT EXISTS WSO2AM_DB;
USE WSO2AM_DB;

-- Grant permissions to wso2carbon user
GRANT ALL PRIVILEGES ON WSO2AM_DB.* TO 'wso2carbon'@'%';
FLUSH PRIVILEGES;

EOF

echo "Docker Compose file created: $docker_compose_file"
echo "MySQL initialization scripts created in mysql-init/"
echo ""
echo "To start the setup, run:"
echo "  docker-compose -f $docker_compose_file up -d"
echo ""
echo "To stop the setup, run:"
echo "  docker-compose -f $docker_compose_file down"
echo ""
echo "To view logs:"
echo "  docker-compose -f $docker_compose_file logs -f wso2am"
