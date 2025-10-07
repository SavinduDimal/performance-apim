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
# Start WSO2 API Manager using Docker (Ultra-Simple Test)
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
    heap_size=$default_heap_size
fi

# Stop existing container if running
if docker ps -a --format "table {{.Names}}" | grep -q "^wso2am$"; then
    echo "Stopping existing WSO2 API Manager container..."
    docker stop wso2am || true
    docker rm wso2am || true
fi

echo "Starting WSO2 APIM container in test mode (no volumes, no custom env)..."

# Check if we can inspect the container first
echo "Inspecting WSO2 APIM Docker image..."
docker run --rm ${docker_image} /bin/bash -c "echo 'Container can start'; java -version; ls -la /home/wso2carbon/wso2am-4.5.0/bin/" || {
    echo "Container inspection failed"
    exit 1
}

# Start the container with absolutely minimal configuration  
docker run -d \
    --name wso2am \
    --hostname localhost \
    -p 9763:9763 \
    -p 9443:9443 \
    -p 8280:8280 \
    -p 8243:8243 \
    ${docker_image} || { echo "Failed to start Docker container"; exit 1; }

# Monitor container startup
for i in {1..6}; do
    sleep 10
    echo "Check $i/6: Container status after $((i*10)) seconds..."
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep wso2am; then
        echo "Container is running"
    else
        echo "Container stopped or not found. Checking logs..."
        docker logs wso2am --tail 20
        exit 1
    fi
done

echo "Container appears stable after 60 seconds"

echo "Container is running. Checking APIM readiness..."

# Check if APIM is responding (shorter timeout for test)
exit_status=100
n=0
until [ $n -ge 20 ]; do
    response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "000")"
    if [ "$response_code" = "200" ]; then
        echo "API Manager started successfully in test mode!"
        exit_status=0
        break
    fi
    echo "Waiting for APIM to respond... (attempt $((n+1))/20, response: $response_code)"
    sleep 15
    n=$(($n + 1))
done

if [ $exit_status -ne 0 ]; then
    echo "API Manager failed to start within expected time"
    echo "Container status:"
    docker ps -a | grep wso2am || echo "Container not found"
    echo "Container logs (last 50 lines):"
    docker logs wso2am --tail 50
    exit 1
fi

echo "WSO2 API Manager test startup completed successfully!"
exit $exit_status
