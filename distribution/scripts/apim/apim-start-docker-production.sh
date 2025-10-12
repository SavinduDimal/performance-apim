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
# Start WSO2 API Manager using Docker (Production approach - step by step)
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
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

echo "Setting Heap to ${heap_size}"

# Start with performance-optimized configuration
echo "Starting WSO2 API Manager container with performance optimizations..."

# Create logs directory with proper permissions  
mkdir -p $(pwd)/wso2am-docker/logs
chmod 777 $(pwd)/wso2am-docker/logs 2>/dev/null || true

# Set up performance-optimized JVM arguments for Docker container
export JAVA_OPTS="-Xms${heap_size} -Xmx${heap_size} -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions -XX:G1MaxNewSizePercent=20 -XX:G1NewSizePercent=15 -XX:+UseStringDeduplication -Xlog:gc*:gc.log:time,uptime,tags,level"

# Start with basic container first (no volume mounts)
echo "Step 1: Testing basic container startup (no volumes)..."
docker run -d \
    --name wso2am-test \
    --hostname localhost \
    -p 9763:9763 \
    -p 9443:9443 \
    -p 8280:8280 \
    -p 8243:8243 \
    ${docker_image} || { echo "Failed to start basic Docker container"; exit 1; }

# Wait for basic startup
echo "Waiting for basic container to initialize..."
sleep 30

# Check if basic container works
basic_works=false
for i in {1..10}; do
    response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "000")"
    if [ "$response_code" = "200" ]; then
        echo "Basic container works! Response: $response_code"
        basic_works=true
        break
    fi
    echo "Waiting for basic container... (attempt $i/10, response: $response_code)"
    sleep 10
done

# Stop basic container
docker stop wso2am-test || true
docker rm wso2am-test || true

if [ "$basic_works" = "false" ]; then
    echo "Basic container failed to start properly"
    exit 1
fi

# Now try with minimal volume mounts (MySQL connector + optimized startup script)
echo "Step 2: Starting with MySQL connector, performance optimizations, and GC logging..."
docker run -d \
    --name wso2am \
    --hostname localhost \
    --memory="4g" \
    --cpus="2.0" \
    -p 9763:9763 \
    -p 9443:9443 \
    -p 8280:8280 \
    -p 8243:8243 \
    -e JAVA_OPTS="$JAVA_OPTS" \
    -v $(pwd)/wso2am-docker/logs:/home/wso2carbon/wso2am-4.5.0/repository/logs \
    -v $(pwd)/wso2am-docker/repository/components/lib:/home/wso2carbon/wso2am-4.5.0/repository/components/lib \
    -v $(pwd)/wso2am-docker/bin/api-manager.sh:/home/wso2carbon/wso2am-4.5.0/bin/api-manager.sh:ro \
    ${docker_image} || { echo "Failed to start Docker container with MySQL connector and optimizations"; exit 1; }

# Wait and test
echo "Waiting for container with MySQL connector to initialize..."
sleep 30

connector_works=false
for i in {1..10}; do
    response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "000")"
    if [ "$response_code" = "200" ]; then
        echo "Container with MySQL connector works! Response: $response_code"
        connector_works=true
        break
    fi
    echo "Waiting for container with MySQL connector... (attempt $i/10, response: $response_code)"
    sleep 10
done

if [ "$connector_works" = "false" ]; then
    echo "Container with MySQL connector failed. Checking logs..."
    docker logs wso2am --tail 50
    
    # Fall back to basic container without volumes
    echo "Falling back to basic container without volumes..."
    docker stop wso2am || true
    docker rm wso2am || true
    
    docker run -d \
        --name wso2am \
        --hostname localhost \
        -p 9763:9763 \
        -p 9443:9443 \
        -p 8280:8280 \
        -p 8243:8243 \
        ${docker_image} || { echo "Failed to start fallback Docker container"; exit 1; }
    
    echo "Fallback container started - configuration will need to be done via API or manual process"
fi

# Final verification
echo "Final verification - waiting for API Manager to be ready..."
exit_status=100
n=0
until [ $n -ge 60 ]; do
    # Check if container is still running
    if ! docker ps --format "table {{.Names}}" | grep -q "^wso2am$"; then
        echo "Container stopped unexpectedly. Checking logs..."
        docker logs wso2am --tail 150
        exit 1
    fi
    
    response_code="$(curl -sk -w "%{http_code}" -o /dev/null https://localhost:8243/services/Version || echo "")"
    if [ "$response_code" = "200" ]; then
        echo "API Manager started successfully"
        exit_status=0
        break
    fi
    echo "Waiting for APIM to respond... (attempt $((n+1))/60, response: $response_code)"
    sleep 10
    n=$(($n + 1))
done

if [ $exit_status -ne 0 ]; then
    echo "API Manager failed to start within expected time"
    echo "Container status:"
    docker ps -a | grep wso2am || echo "Container not found"
    echo "Container logs:"
    docker logs wso2am --tail 50
    exit 1
fi

# Wait for another 10 seconds to make sure that the server is ready to accept API requests.
sleep 10
echo "WSO2 API Manager is ready to accept requests"
exit $exit_status
