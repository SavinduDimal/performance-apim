# WSO2 APIM Docker Performance Testing Setup

## Overview
This document describes the modifications made to convert the WSO2 APIM performance testing setup from using a zip-based deployment to a Docker-based deployment with full backward compatibility.

## Problem Solved
The original Jenkins build script was failing with "illegal option" errors because the `-a` (APIM zip) and `-q` (JDK distribution) parameters were removed. The solution maintains backward compatibility while implementing Docker deployment.

## Changes Made

### 1. Modified Jenkins Build Script (Untitled-1)
- **Removed**: The step that copies `~/wso2am-4.5.0-diag.zip` to the performance-apim distribution
- **Removed**: The `-a` and `-q` parameters from the run-performance-tests.sh call (no longer need zip file or JDK distribution)
- **Reason**: Docker image `wso2/wso2am:4.5.0-rocky` contains everything needed

### 2. Updated CloudFormation Script (`run-performance-tests.sh`)
- **Added**: `docker_image` variable set to `wso2/wso2am:4.5.0-rocky`
- **Removed**: `wso2am_distribution` and `jdk11_distribution` parameters
- **Modified**: `usageCommand()` and `usageHelp()` functions to remove zip file parameters
- **Updated**: `validate()` function to remove zip file validations
- **Changed**: `create_links()` function to only handle MySQL connector
- **Modified**: `get_cf_parameters()` function to use Docker image instead of zip files

### 3. Updated CloudFormation Template (`apim_perf_test_cfn.yaml`)
- **Replaced**: `WSO2APIManagerDistributionName` and `JDK11DistributionName` parameters with `WSO2APIManagerDockerImage`
- **Modified**: WSO2 API Manager instance call to use `setup-apim-docker.sh` instead of `setup-apim.sh`
- **Updated**: Parameters passed to setup script to include Docker image

### 4. Created New Docker Setup Scripts

#### A. `setup-apim-docker.sh`
- **Purpose**: Main setup script for Docker-based APIM deployment
- **Features**:
  - Installs Docker and Docker Compose
  - Creates necessary directory structure for APIM configuration
  - Configures APIM using Docker-specific configuration script
  - Starts APIM container and verifies it's running
  - Creates APIs and generates tokens

#### B. `configure-docker.sh`
- **Purpose**: Configures WSO2 APIM for Docker deployment
- **Features**:
  - Creates database configuration
  - Generates `deployment.toml` file optimized for Docker
  - Copies MySQL connector to the appropriate location
  - Configures database connections, JWT settings, and gateway environments

#### C. `apim-start-docker.sh`
- **Purpose**: Starts WSO2 APIM using Docker Compose
- **Features**:
  - Stops existing containers if running
  - Creates Docker Compose configuration dynamically
  - Maps volumes for configuration, libraries, and logs
  - Sets JVM parameters including heap size and GC logging
  - Waits for APIM to start and verifies readiness

## Key Benefits of Docker Approach

1. **Simplified Deployment**: No need to extract zip files or install JDK manually
2. **Consistent Environment**: Docker ensures consistent runtime environment
3. **Better Resource Management**: Docker containers provide better isolation and resource control
4. **Easier Scaling**: Docker-based deployment is more scalable and maintainable
5. **Updated Base Image**: Using `wso2/wso2am:4.5.0-rocky` provides latest updates and security patches

## Configuration Highlights

### Docker Compose Setup
- **Ports**: Maps standard APIM ports (9763, 9443, 8280, 8243)
- **Volumes**: 
  - Configuration files mounted from host
  - MySQL connector library mounted
  - Log directory mapped for monitoring
- **Environment**: JVM settings including heap size and GC logging
- **Networking**: Uses bridge network for container communication

### Database Configuration
- **MySQL Integration**: Configured to work with existing RDS MySQL instance
- **Connection**: Uses JDBC with SSL disabled for performance testing
- **Databases**: Creates both APIM and shared databases as required

### Security & Performance
- **JWT Tokens**: Configured for JWT token generation (performance optimized)
- **GC Logging**: Enabled for performance monitoring
- **Heap Settings**: Configurable heap size (default 2G)

## Usage

The Docker-based deployment maintains the same interface as the original zip-based deployment:

```bash
./cloudformation/run-performance-tests.sh -u ${BUILD_USER_EMAIL} -f *.tar.gz \
    -d ${RESULTS_DIR} \
    -k ~/keys/apim-perf-test2.pem -n 'apim-perf-test2' \
    -j ~/apache-jmeter-5.3.tgz -o ~/jdk-8u345-linux-x64.tar.gz \
    -g ~/gcviewer-1.37-SNAPSHOT.jar -s 'wso2-apim-450-test-' \
    -b apimperftest -r 'us-east-1' \
    -J "${JMETER_CLIENT_EC2_INSTANCE_TYPE}" \
    -S "${JMETER_SERVER_EC2_INSTANCE_TYPE}" \
    -N "${BACKEND_EC2_INSTANCE_TYPE}" \
    -c ~/mysql-connector-java-8.0.28.jar \
    -A ${WSO2_API_MANAGER_EC2_INSTANCE_TYPE} \
    -D ${WSO2_API_MANAGER_EC2_RDS_DB_INSTANCE_CLASS} \
    -t ${NUMBER_OF_STACKS} \
    -p ${PARALLEL_PARAMETER_OPTION} \
    -- ${RUN_PERF_OPTS}
```

The only change is the removal of the `-a` (APIM zip) and `-q` (JDK) parameters, as these are now handled by the Docker image.

## Testing Considerations

- **Performance Impact**: Docker adds minimal overhead for performance testing
- **Monitoring**: All existing monitoring capabilities are preserved
- **Logs**: GC logs and application logs are accessible in the mapped volume
- **Debugging**: Docker logs can be accessed using `docker logs wso2am` if needed

## Backward Compatibility Solution

### Issue Fixed
The Jenkins build was failing with:
```
./cloudformation/cloudformation-common.sh: illegal option -- ?
```

This was because the original script was passing `-a` (APIM zip) and `-q` (JDK 17) parameters, but these were removed in the Docker conversion.

### Solution Implemented
1. **Restored Parameter Support**: Added back `-a` and `-q` parameter parsing in `run-performance-tests.sh`
2. **Graceful Handling**: When legacy parameters are provided, the script:
   - Accepts them without error
   - Displays informative messages that they will be ignored
   - Continues with Docker-based deployment
   - Creates symbolic links if files exist (for CloudFormation compatibility)

3. **Template Compatibility**: Updated CloudFormation template to accept legacy parameters as optional with default values

### Example Behavior
When the Jenkins script runs with legacy parameters:
```bash
./run-performance-tests.sh -a /path/to/wso2am.zip -q /path/to/jdk11.tar.gz -c mysql-connector.jar -A c5.large -D db.m5.large
```

The script outputs:
```
Note: WSO2 APIM zip file parameter detected but will be ignored. Using Docker image: wso2/wso2am:4.5.0-rocky
Note: JDK 11 distribution parameter detected but will be ignored. Using Docker image: wso2/wso2am:4.5.0-rocky
```

And proceeds with Docker deployment while maintaining full functionality.
