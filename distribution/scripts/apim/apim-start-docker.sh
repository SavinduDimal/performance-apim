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
# Start WSO2 API Manager using Docker
# ----------------------------------------------------------------------------

default_heap_size="2G"
heap_size="$default_heap_size"
docker_image=""

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -i <docker_image> [-m <heap_size>] [-h]"
    echo "-i: Docker image for WSO2 API Manager."
    echo "-m: The heap memory size of API Manager. Default: $default_heap_size."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "i:m:h" opt; do
    case "${opt}" in
    i)
        docker_image=${OPTARG}
        ;;
    m)
        heap_size=${OPTARG}
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

if [[ -z $docker_image ]]; then
    echo "Please provide the Docker image for WSO2 API Manager."
    exit 1
fi

if [[ -z $heap_size ]]; then
    echo "Please provide the heap size for the API Manager."
    exit 1
fi

# Stop existing container if running
if docker ps -a --format "table {{.Names}}" | grep -q "^wso2am$"; then
    echo "Stopping existing WSO2 API Manager container..."
    docker stop wso2am || true
    docker rm wso2am || true
fi

# Clean up log files
if [ -d wso2am-docker/logs ]; then
    echo "Log files exist. Moving to /tmp"
    mv wso2am-docker/logs/* /tmp/ 2>/dev/null || true
fi

# Create logs directory
mkdir -p wso2am-docker/logs

echo "Setting Heap to ${heap_size}"

# Create docker-compose.yml for easier management
cat > docker-compose.yml << EOF
version: '3.8'
services:
  wso2am:
    image: ${docker_image}
    container_name: wso2am
    hostname: localhost
    ports:
      - "9763:9763"
      - "9443:9443"
      - "8280:8280"
      - "8243:8243"
    volumes:
      - ./wso2am-docker/repository/conf/deployment.toml:/home/wso2carbon/wso2am-4.5.0/repository/conf/deployment.toml
      - ./wso2am-docker/repository/components/lib:/home/wso2carbon/wso2am-4.5.0/repository/components/lib
      - ./wso2am-docker/logs:/home/wso2carbon/wso2am-4.5.0/repository/logs
    environment:
      - JAVA_OPTS=-Xms${heap_size} -Xmx${heap_size} -Xlog:gc*,safepoint,gc+heap=trace:file=/home/wso2carbon/wso2am-4.5.0/repository/logs/gc.log:uptime,utctime,level,tags
    restart: unless-stopped
    networks:
      - wso2am-network

networks:
  wso2am-network:
    driver: bridge
EOF

echo "Starting WSO2 API Manager Docker container..."
docker-compose up -d

echo "Waiting for API Manager to start..."
exit_status=100
n=0
until [ $n -ge 60 ]; do
    response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "")"
    if [ $response_code -eq 200 ]; then
        echo "API Manager started successfully"
        exit_status=0
        break
    fi
    sleep 10
    n=$(($n + 1))
done

if [ $exit_status -ne 0 ]; then
    echo "API Manager failed to start within expected time"
    echo "Container logs:"
    docker logs wso2am --tail 50
    exit 1
fi

# Wait for another 10 seconds to make sure that the server is ready to accept API requests.
sleep 10
echo "WSO2 API Manager is ready to accept requests"
exit $exit_status
