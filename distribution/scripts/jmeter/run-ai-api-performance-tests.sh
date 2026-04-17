#!/bin/bash -e
# Copyright (c) 2026, WSO2 Inc. (http://wso2.org) All Rights Reserved.
#
# ----------------------------------------------------------------------------
# Run API Manager AI API Performance Tests
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
. $script_dir/perf-test-common.sh

payload_generator_args=("-a")

function initialize() {
    export apim_ssh_host=apim
    export apim_host=$(get_ssh_hostname $apim_ssh_host)
    export backend_host=$(get_ssh_hostname $backend_ssh_host)
}
export -f initialize

declare -A test_scenario0=(
    [name]="ai_api_direct"
    [display_name]="AI API Direct"
    [description]="Direct invocation of the mock AI backend, bypassing the API gateway."
    [jmx]="ai-api-test.jmx"
    [protocol]="http"
    [path]="/v1/chat/completions"
    [host_type]="backend"
    [port]="3000"
    [use_apim]=false
    [use_backend]=true
    [backend_flags]="--port 3000 --ai-chat-completion-response"
    [skip]=false
)
declare -A test_scenario1=(
    [name]="ai_api_passthrough"
    [display_name]="AI API Passthrough"
    [description]="AI API invocation through the API gateway to the mock AI backend."
    [jmx]="ai-api-test.jmx"
    [protocol]="https"
    [path]="/aiapi/1.0.0/v1/chat/completions"
    [host_type]="apim"
    [port]="8243"
    [use_apim]=true
    [use_backend]=true
    [backend_flags]="--port 3000 --ai-chat-completion-response"
    [skip]=false
)

function before_execute_test_scenario() {
    local service_host=$apim_host
    if [[ ${scenario[host_type]} == "backend" ]]; then
        service_host=$backend_host
    fi

    jmeter_params+=("host=$service_host" "port=${scenario[port]}" "path=${scenario[path]}")
    jmeter_params+=("payload=$HOME/ai_${msize}B.json" "protocol=${scenario[protocol]}")

    if [[ ${scenario[use_apim]} == true ]]; then
        echo "Starting APIM service"
        ssh $apim_ssh_host "./apim/apim-start.sh -m $heap"
    fi
}

function after_execute_test_scenario() {
    if [[ ${scenario[use_apim]} == true ]]; then
        write_server_metrics apim $apim_ssh_host org.wso2.carbon.bootstrap.Bootstrap
        download_file $apim_ssh_host wso2am/repository/logs/wso2carbon.log wso2carbon.log
        download_file $apim_ssh_host wso2am/repository/logs/gc.log apim_gc.log
    fi
}

test_scenarios
