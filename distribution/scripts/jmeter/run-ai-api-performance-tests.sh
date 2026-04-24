#!/bin/bash -e
# Copyright (c) 2026, WSO2 Inc. (http://wso2.org) All Rights Reserved.
#
# ----------------------------------------------------------------------------
# Run API Manager AI API Performance Tests
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
export PAYLOAD_GENERATOR_ARGS="-a"
jwt_tokens_file_name="jwt-tokens.csv"
jwt_tokens_count=4000
. $script_dir/perf-test-common.sh

function initialize() {
    export apim_ssh_host=apim
    export apim_host=$(get_ssh_hostname $apim_ssh_host)
    export backend_host=$(get_ssh_hostname $backend_ssh_host)
    echo "Generating ${jwt_tokens_count} JWT tokens on APIM."
    ssh $apim_ssh_host "./apim/generate-jwt-tokens.sh -t ${jwt_tokens_count} -a ${jwt_tokens_file_name}"
    echo "Downloading JWT tokens to $HOME."
    scp $apim_ssh_host:apim/target/${jwt_tokens_file_name} $HOME/
    if [[ $jmeter_servers -gt 1 ]]; then
        for jmeter_ssh_host in ${jmeter_ssh_hosts[@]}; do
            echo "Copying JWT tokens to $jmeter_ssh_host"
            scp $HOME/${jwt_tokens_file_name} $jmeter_ssh_host:
        done
    fi
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
    [name]="ai_api_auth_no_guardrails"
    [display_name]="AI API Auth No Guardrails"
    [description]="AI API invocation through the API gateway with authentication enabled and no guardrails."
    [jmx]="ai-api-test.jmx"
    [protocol]="https"
    [path]="/aiapi-auth/1.0.0/v1/chat/completions"
    [host_type]="apim"
    [port]="8243"
    [use_apim]=true
    [use_backend]=true
    [backend_flags]="--port 3000 --ai-chat-completion-response"
    [skip]=false
)
declare -A test_scenario2=(
    [name]="ai_api_pii_masking"
    [display_name]="AI API PII Masking"
    [description]="AI API invocation through the API gateway with authentication and PII masking on request and response."
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
declare -A test_scenario3=(
    [name]="ai_api_advanced_guardrails"
    [display_name]="AI API Advanced Guardrails"
    [description]="AI API invocation through the API gateway with authentication, request PII masking, URL and JSON schema guardrails, and response PII masking."
    [jmx]="ai-api-test.jmx"
    [protocol]="https"
    [path]="/aiapi-advanced/1.0.0/v1/chat/completions"
    [host_type]="apim"
    [port]="8243"
    [use_apim]=true
    [use_backend]=true
    [backend_flags]="--port 3000 --ai-chat-completion-response"
    [skip]=false
)

function before_execute_test_scenario() {
    local service_host=$apim_host
    local response_size=${rsize:-1024}
    if [[ ${scenario[host_type]} == "backend" ]]; then
        service_host=$backend_host
    fi

    jmeter_params+=("host=$service_host" "port=${scenario[port]}" "path=${scenario[path]}")
    jmeter_params+=("payload=$HOME/ai_${msize}B.json" "protocol=${scenario[protocol]}")
    jmeter_params+=("tokens=$HOME/${jwt_tokens_file_name}" "response_size=${response_size}")
    if [[ ! -f $HOME/ai_${msize}B.json ]]; then
        echo "AI API payload file is missing: $HOME/ai_${msize}B.json"
        exit 1
    fi
    if [[ ! -f $HOME/${jwt_tokens_file_name} ]]; then
        echo "JWT token file is missing: $HOME/${jwt_tokens_file_name}"
        exit 1
    fi

    scenario[backend_flags]="--port 3000 --ai-chat-completion-response --ai-chat-completion-response-size ${response_size}"

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
