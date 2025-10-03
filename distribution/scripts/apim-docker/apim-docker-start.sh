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
# Start WSO2 API Manager using Docker (replaces apim-start.sh)
# ----------------------------------------------------------------------------

default_heap_size="2G"
default_docker_image="wso2/wso2am:4.5.0-rocky"
heap_size="$default_heap_size"
docker_image="$default_docker_image"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 [-i <docker_image>] [-m <heap_size>] [-h]"
    echo "-i: The Docker image to use. Default: $default_docker_image."
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

if [[ -z $heap_size ]]; then
    echo "Please provide the heap size for the API Manager."
    exit 1
fi

if [[ -z $docker_image ]]; then
    echo "Please provide the Docker image for the API Manager."
    exit 1
fi

# Stop existing APIM container if running (similar to original apim-start.sh stopping process)
if docker ps -a --format "table {{.Names}}" | grep -q "^wso2am-instance$"; then
    echo "Shutting down existing APIM Docker container"
    docker stop wso2am-instance || true
    docker rm wso2am-instance || true
fi

# Create directories for volumes if they don't exist
mkdir -p wso2am/repository/{logs,components/lib}

# Set Java options for the container (same as original script)
JAVA_OPTS="-Xms${heap_size} -Xmx${heap_size}"

# Determine Java version for GC logging (from original apim-start.sh logic)
if [[ $docker_image == *"jdk11"* ]] || [[ $docker_image == *"jdk17"* ]]; then
    # JDK 11+ GC logging 
    JAVA_OPTS="$JAVA_OPTS -Xlog:gc*,safepoint,gc+heap=trace:/home/wso2carbon/wso2am-4.5.0/repository/logs/gc.log:uptime,utctime,level,tags"
else
    # JDK 8 GC logging
    JAVA_OPTS="$JAVA_OPTS -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/home/wso2carbon/wso2am-4.5.0/repository/logs/gc.log"
fi

echo "Setting Heap to ${heap_size}"
echo "Enabling GC Logs"
echo "Starting APIM using Docker image: $docker_image"

# Start WSO2 API Manager container 
docker run -d \
    --name wso2am-instance \
    -p 8280:8280 \
    -p 8243:8243 \
    -p 9443:9443 \
    -p 9999:9999 \
    -p 11111:11111 \
    -e JAVA_OPTS="$JAVA_OPTS" \
    -v $(pwd)/wso2am/repository/conf:/home/wso2carbon/wso2am-4.5.0/repository/conf \
    -v $(pwd)/wso2am/repository/logs:/home/wso2carbon/wso2am-4.5.0/repository/logs \
    -v $(pwd)/wso2am/repository/components/lib:/home/wso2carbon/wso2am-4.5.0/repository/components/lib \
    $docker_image

echo "Waiting for API Manager to start"

# Wait for API Manager to start (same logic as original apim-start.sh)
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

# Wait for another 10 seconds to make sure that the server is ready to accept API requests.
sleep 10
exit $exit_status
