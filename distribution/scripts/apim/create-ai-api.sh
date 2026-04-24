#!/bin/bash -e
# Copyright 2026 WSO2 Inc. (http://wso2.org)
#
# ----------------------------------------------------------------------------
# Create an AI API in WSO2 API Manager for performance tests.
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
apim_host=""
api_name=""
api_description="AI API Performance Test API"
backend_endpoint_url=""
api_version="1.0.0"
auth="admin:admin"
openapi_file="$script_dir/payload/mistral_api.yaml"
api_mode="pii_masking"
default_api_mode="$api_mode"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -a <apim_host> -n <api_name> -b <backend_endpoint_url> [-d <api_description>] [-f <openapi_file>] [-m <api_mode>] [-h]"
    echo ""
    echo "-a: Hostname of WSO2 API Manager."
    echo "-n: API context/name prefix. The API name will be <api_name>API."
    echo "-b: Mock AI backend endpoint URL."
    echo "-d: API Description."
    echo "-f: OpenAPI file to import. Default: $openapi_file"
    echo "-m: AI API scenario mode. One of: no_guardrails, pii_masking, advanced_guardrails. Default: $default_api_mode"
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "a:n:d:b:f:m:h" opt; do
    case "${opt}" in
    a)
        apim_host=${OPTARG}
        ;;
    n)
        api_name=${OPTARG}
        ;;
    d)
        api_description=${OPTARG}
        ;;
    b)
        backend_endpoint_url=${OPTARG}
        ;;
    f)
        openapi_file=${OPTARG}
        ;;
    m)
        api_mode=${OPTARG}
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

if [[ -z $apim_host ]]; then
    echo "Please provide the Hostname of WSO2 API Manager."
    exit 1
fi

if [[ -z $api_name ]]; then
    echo "Please provide the API Name."
    exit 1
fi

if [[ -z $backend_endpoint_url ]]; then
    echo "Please provide the backend endpoint URL."
    exit 1
fi

if [[ ! -f $openapi_file ]]; then
    echo "Please provide a valid OpenAPI file. File not found: $openapi_file"
    exit 1
fi

if [[ $api_mode != "no_guardrails" && $api_mode != "pii_masking" && $api_mode != "advanced_guardrails" ]]; then
    echo "Please provide a valid AI API mode. Supported values: no_guardrails, pii_masking, advanced_guardrails."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq."
    exit 1
fi

base_https_url="https://${apim_host}:9443"
api_display_name="${api_name}API"
api_context="${api_name}"
curl_command="curl -sk"
pii_guardrail_policy_name="PIIMaskingRegex"
url_guardrail_policy_name="URLGuardrail"
json_schema_guardrail_policy_name="JSONSchemaGuardrail"
target_dir="$script_dir/target"
mkdir -p "$target_dir"

client_request() {
    cat <<EOF
{
    "callbackUrl": "wso2.org",
    "clientName": "setup_ai_apim_script",
    "tokenScope": "Production",
    "owner": "admin",
    "grantType": "password refresh_token",
    "saasApp": true
}
EOF
}

app_request() {
    cat <<EOF
{
   "name":"PerformanceTestAPP",
   "throttlingPolicy":"Unlimited",
   "description":"PerformanceTestAPP",
   "tokenType":"JWT",
   "attributes":{}
}
EOF
}

generate_keys_request() {
    cat <<EOF
{
   "keyType":"PRODUCTION",
   "grantTypesToBeSupported":[
      "refresh_token",
      "password",
      "client_credentials",
      "urn:ietf:params:oauth:grant-type:jwt-bearer"
   ],
   "callbackUrl":"wso2.org"
}
EOF
}

subscription_request() {
    cat <<EOF
{
   "apiId":"$1",
   "applicationId":"$application_id",
   "throttlingPolicy":"Unlimited"
}
EOF
}

client_credentials=$($curl_command -u admin:admin -H "Content-Type: application/json" \
    -d "$(client_request)" "${base_https_url}/client-registration/v0.17/register" \
    | jq -r '.clientId + ":" + .clientSecret')

get_access_token() {
    local access_token
    access_token=$($curl_command -d "grant_type=password&username=admin&password=admin&scope=apim:$1" \
        -u "$client_credentials" "${base_https_url}/oauth2/token" | jq -r '.access_token')
    echo "$access_token"
}

get_admin_access_token() {
    local access_token
    access_token=$($curl_command -d "grant_type=password&username=admin&password=admin&scope=apim:admin+apim:api_create+apim:api_delete+apim:api_generate_key+apim:api_import_export+apim:api_product_import_export+apim:api_publish+apim:api_view+apim:app_import_export+apim:app_manage+apim:subscribe+apim:sub_manage+apim:subscription_block+apim:subscription_view+apim:mediation_policy_create+apim:mediation_policy_manage+apim:mediation_policy_view+apim:common_operation_policy_manage+apim:publisher_settings+apim:shared_scope_manage+apim:threat_protection_policy_create+apim:threat_protection_policy_manage+openid+service_catalog:service_view+service_catalog:service_write" \
        -u "$client_credentials" "${base_https_url}/oauth2/token" | jq -r '.access_token')
    echo "$access_token"
}

view_access_token=$(get_access_token api_view)
create_access_token=$(get_access_token api_create)
publish_access_token=$(get_access_token api_publish)
subscribe_access_token=$(get_access_token subscribe)
app_access_token=$(get_access_token app_manage)
sub_manage_token=$(get_access_token sub_manage)
admin_token=$(get_admin_access_token)

function ensure_performance_app_and_keys() {
    echo "Getting PerformanceTestAPP ID"
    application_id=$($curl_command -H "Authorization: Bearer $subscribe_access_token" \
        "${base_https_url}/api/am/devportal/v3/applications?query=PerformanceTestAPP" | jq -r '.list[0] | .applicationId')

    if [[ -z $application_id || $application_id == "null" ]]; then
        echo "Creating PerformanceTestAPP application"
        application_id=$($curl_command -X POST -H "Authorization: Bearer $app_access_token" \
            -H "Content-Type: application/json" -d "$(app_request)" \
            "${base_https_url}/api/am/devportal/applications" | jq -r '.applicationId')
    fi

    if [[ -z $application_id || $application_id == "null" ]]; then
        echo "Failed to find or create PerformanceTestAPP."
        exit 1
    fi
    echo "$application_id" >"$target_dir/application_id"

    echo "Finding Consumer Key for PerformanceTestAPP"
    keys_response=$($curl_command -H "Authorization: Bearer $subscribe_access_token" \
        "${base_https_url}/api/am/devportal/v3/applications/$application_id/keys/PRODUCTION")
    consumer_key=$(echo "$keys_response" | jq -r '.consumerKey')
    if [[ -z $consumer_key || $consumer_key == "null" ]]; then
        keys_response=$($curl_command -H "Authorization: Bearer $app_access_token" \
            -H "Content-Type: application/json" -d "$(generate_keys_request)" \
            "${base_https_url}/api/am/devportal/v3/applications/$application_id/generate-keys")
        consumer_key=$(echo "$keys_response" | jq -r '.consumerKey')
    fi
    if [[ -z $consumer_key || $consumer_key == "null" ]]; then
        echo "Failed to generate keys for PerformanceTestAPP."
        exit 1
    fi
    echo "$consumer_key" >"$target_dir/consumer_key"
}

function get_operation_policy_id() {
    local policy_name="$1"
    local policy_response
    local policy_id

    policy_response=$($curl_command -H "Authorization: Bearer $admin_token" -H "accept: application/json" \
        "${base_https_url}/api/am/publisher/v4/operation-policies?query=name%3A${policy_name}" || true)
    policy_id=$(echo "$policy_response" | jq -r '.list[0].id // .list[0].policyId // empty' 2>/dev/null || true)
    if [[ -z $policy_id ]]; then
        echo "Could not find operation policy ID for ${policy_name}." >&2
        echo "Response: ${policy_response}" >&2
        exit 1
    fi
    echo "$policy_id"
}

function build_api_policies_json() {
    local mode="$1"
    local pii_policy_id="$2"
    local url_policy_id="$3"
    local json_schema_policy_id="$4"

    case "$mode" in
    no_guardrails)
        jq -nc '{"request":[],"response":[],"fault":[]}'
        ;;
    pii_masking)
        jq -nc \
            --arg pii_policy_id "$pii_policy_id" \
            --arg pii_entities '[{"piiEntity":"EMAIL","piiRegex":"([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\\\\.[a-zA-Z0-9_-]+)"}]' \
            '{
              "request":[{
                "policyName":"PIIMaskingRegex",
                "policyId":$pii_policy_id,
                "policyVersion":"v1.0",
                "policyType":"common",
                "parameters":{
                  "name":"Mask Email PII",
                  "piiEntities":$pii_entities,
                  "jsonPath":"$.messages[-1].content",
                  "redact":"false"
                }
              }],
              "response":[{
                "policyName":"PIIMaskingRegex",
                "policyId":$pii_policy_id,
                "policyVersion":"v1.0",
                "policyType":"common",
                "parameters":{
                  "name":"Mask Email PII",
                  "piiEntities":$pii_entities,
                  "jsonPath":"$.choices[0].message.content",
                  "redact":"false"
                }
              }],
              "fault":[]
            }'
        ;;
    advanced_guardrails)
        jq -nc \
            --arg pii_policy_id "$pii_policy_id" \
            --arg url_policy_id "$url_policy_id" \
            --arg json_schema_policy_id "$json_schema_policy_id" \
            --arg pii_entities '[{"piiEntity":"EMAIL","piiRegex":"([a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\\\\.[a-zA-Z0-9_-]+)"}]' \
            --arg schema '{"$schema":"http://json-schema.org/draft-07/schema#","type":"object"}' \
            '{
              "request":[
                {
                  "policyName":"PIIMaskingRegex",
                  "policyId":$pii_policy_id,
                  "policyVersion":"v1.0",
                  "policyType":"common",
                  "parameters":{
                    "name":"Mask Email PII",
                    "piiEntities":$pii_entities,
                    "jsonPath":"$.messages[-1].content",
                    "redact":"false"
                  }
                },
                {
                  "policyName":"JSONSchemaGuardrail",
                  "policyId":$json_schema_policy_id,
                  "policyVersion":"v1.0",
                  "policyType":"common",
                  "parameters":{
                    "name":"JSON Schema Guardrail",
                    "schema":$schema,
                    "showAssessment":true
                  }
                },
                {
                  "policyName":"URLGuardrail",
                  "policyId":$url_policy_id,
                  "policyVersion":"v1.0",
                  "policyType":"common",
                  "parameters":{
                    "name":"URL Safety Guard",
                    "showAssessment":"false",
                    "jsonPath":"$.messages[-1].content",
                    "timeout":"3000",
                    "onlyDNS":"false"
                  }
                }
              ],
              "response":[{
                "policyName":"PIIMaskingRegex",
                "policyId":$pii_policy_id,
                "policyVersion":"v1.0",
                "policyType":"common",
                "parameters":{
                  "name":"Mask Email PII",
                  "piiEntities":$pii_entities,
                  "jsonPath":"$.choices[0].message.content",
                  "redact":"false"
                }
              }],
              "fault":[]
            }'
        ;;
    esac
}

function update_unauthenticated_subscription_policy() {
    echo "Updating Unauthenticated subscription throttling policy"
    local policies_response
    policies_response=$($curl_command -u "${auth}" \
        -H "accept: application/json" \
        "${base_https_url}/api/am/admin/v4/throttling/policies/subscription")

    local policy_id
    policy_id=$(echo "$policies_response" | jq -r '.list[] | select(.policyName=="Unauthenticated") | .policyId')
    if [[ -z $policy_id || $policy_id == "null" ]]; then
        echo "Could not find the Unauthenticated subscription throttling policy."
        exit 1
    fi

    local updated_policy
    updated_policy=$(echo "$policies_response" | jq \
        '.list[] | select(.policyName=="Unauthenticated")
        | .description = "Allows unlimited request(s) per minute"
        | .defaultLimit.type = "REQUESTCOUNTLIMIT"
        | .defaultLimit.requestCount.timeUnit = "min"
        | .defaultLimit.requestCount.unitTime = 1
        | .defaultLimit.requestCount.requestCount = 2147483647
        | .defaultLimit.bandwidth = null
        | .defaultLimit.eventCount = null
        | .defaultLimit.aiApiQuota = null')

    local update_response_file="/tmp/update-unauthenticated-policy-response-$$.json"
    local update_status
    update_status=$($curl_command -w "%{http_code}" -o "$update_response_file" \
        -u "${auth}" -X PUT \
        -H "Content-Type: application/json" \
        -d "$updated_policy" \
        "${base_https_url}/api/am/admin/v4/throttling/policies/subscription/${policy_id}")
    if [[ $update_status -lt 200 || $update_status -ge 300 ]]; then
        echo "Failed to update the Unauthenticated subscription throttling policy. HTTP status: ${update_status}. Response:"
        cat "$update_response_file"
        exit 1
    fi
    rm -f "$update_response_file"
}

update_unauthenticated_subscription_policy
ensure_performance_app_and_keys
pii_guardrail_policy_id=""
url_guardrail_policy_id=""
json_schema_guardrail_policy_id=""
if [[ $api_mode == "pii_masking" || $api_mode == "advanced_guardrails" ]]; then
    pii_guardrail_policy_id=$(get_operation_policy_id "$pii_guardrail_policy_name")
fi
if [[ $api_mode == "advanced_guardrails" ]]; then
    url_guardrail_policy_id=$(get_operation_policy_id "$url_guardrail_policy_name")
    json_schema_guardrail_policy_id=$(get_operation_policy_id "$json_schema_guardrail_policy_name")
fi
api_policies_json=$(build_api_policies_json "$api_mode" "$pii_guardrail_policy_id" "$url_guardrail_policy_id" "$json_schema_guardrail_policy_id")

echo "Fetching MistralAI LLM provider ID"
llm_provider_id=$($curl_command "${base_https_url}/api/am/publisher/v4/ai-service-providers" \
    -u "${auth}" -H "accept: application/json" \
    | jq -r '.list[] | select(.name=="MistralAI" and .deprecated==false) | .id')

if [[ -z $llm_provider_id || $llm_provider_id == "null" ]]; then
    echo "Could not find the MistralAI LLM provider."
    exit 1
fi

existing_api_id=$($curl_command -H "Authorization: Bearer $view_access_token" \
    "${base_https_url}/api/am/publisher/v4/apis?query=name:${api_display_name}\$" | jq -r '.list[0] | .id')

if [[ -n $existing_api_id && $existing_api_id != "null" ]]; then
    existing_subscription_id=$($curl_command -H "Authorization: Bearer $subscribe_access_token" \
        "${base_https_url}/api/am/devportal/v3/subscriptions?apiId=$existing_api_id" | jq -r '.list[0] | .subscriptionId')
    if [[ -n $existing_subscription_id && $existing_subscription_id != "null" ]]; then
        echo "Deleting existing subscription ${existing_subscription_id} for ${api_display_name}"
        $curl_command -w "%{http_code}" -o /dev/null -H "Authorization: Bearer $subscribe_access_token" -X DELETE \
            "${base_https_url}/api/am/devportal/v3/subscriptions/${existing_subscription_id}"
    fi
    echo "Deleting existing ${api_display_name} API with ID ${existing_api_id}"
    $curl_command -w "%{http_code}" -o /dev/null -H "Authorization: Bearer $create_access_token" -X DELETE \
        "${base_https_url}/api/am/publisher/v4/apis/${existing_api_id}"
fi

echo "Importing OpenAPI definition for ${api_display_name} from ${openapi_file}"
create_response=$($curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/import-openapi" \
    -H "Authorization: Bearer $create_access_token" \
    -H "accept: application/json" \
    -F "inlineAPIDefinition=<${openapi_file}" \
    -F 'additionalProperties={"name":"'"${api_display_name}"'","version":"'"${api_version}"'","context":"'"${api_context}"'","gatewayType":"wso2/synapse","policies":["Unlimited"],"subtypeConfiguration":{"subtype":"AIAPI","configuration":{"llmProviderId":"'"${llm_provider_id}"'"}},"securityScheme":["api_key","oauth_basic_auth_api_key_mandatory","oauth2"],"egress":true,"endpointConfig":{"endpoint_type":"http","production_endpoints":{"url":"'"${backend_endpoint_url}"'"}}}')

api_id=$(echo "$create_response" | jq -r '.id')
if [[ -z $api_id || $api_id == "null" ]]; then
    echo "Failed to create AI API. Response:"
    echo "$create_response" | jq .
    exit 1
fi

echo "Updating AI API swagger security for chat completions"
swagger_definition=$(jq -nc \
    --arg title "$api_display_name" \
    --arg version "$api_version" \
    --arg description "$api_description" \
    --arg backend "$backend_endpoint_url" \
    --arg base_path "/${api_context}/${api_version}" \
    '{
      "openapi":"3.1.0",
      "info":{"title":$title,"description":$description,"version":$version},
      "servers":[{"url":$backend,"description":"Mock AI backend"}],
      "security":[{"default":[]}],
      "tags":[{"name":"chat","description":"Chat Completion API.","x-displayName":"Chat"}],
      "paths":{
        "/v1/chat/completions":{
          "post":{
            "tags":["chat"],
            "summary":"Chat Completion",
            "operationId":"chat_completion_v1_chat_completions_post",
            "requestBody":{
              "required":true,
              "content":{"application/json":{"schema":{"type":"object"}}}
            },
            "responses":{
              "200":{
                "description":"Successful Response",
                "content":{"application/json":{"schema":{"type":"object"}}}
              }
            },
            "security":[{"default":[]}],
            "x-auth-type":"Application & Application User",
            "x-throttling-tier":"Unlimited",
            "x-wso2-application-security":{"security-types":["api_key"],"optional":false}
          }
        }
      },
      "components":{
        "securitySchemes":{
          "ApiKey":{"type":"http","scheme":"bearer"},
          "default":{"type":"oauth2","flows":{"implicit":{"authorizationUrl":"https://test.com","scopes":{}}}}
        }
      },
      "x-wso2-auth-header":"Authorization",
      "x-wso2-api-key-header":"ApiKey",
      "x-wso2-cors":{
        "corsConfigurationEnabled":false,
        "accessControlAllowOrigins":["*"],
        "accessControlAllowCredentials":false,
        "accessControlAllowHeaders":["authorization","Access-Control-Allow-Origin","Content-Type","SOAPAction","apikey","Internal-Key"],
        "accessControlAllowMethods":["GET","PUT","POST","DELETE","PATCH","OPTIONS"]
      },
      "x-wso2-production-endpoints":{"urls":[$backend],"type":"http"},
      "x-wso2-basePath":$base_path,
      "x-wso2-transports":["http","https"],
      "x-wso2-application-security":{"security-types":["api_key"],"optional":false},
      "x-wso2-response-cache":{"enabled":false,"cacheTimeoutInSeconds":300}
    }')
swagger_response_file="/tmp/create-ai-api-swagger-response-$$.json"
swagger_status=$($curl_command -w "%{http_code}" -o "$swagger_response_file" \
    -X PUT "${base_https_url}/api/am/publisher/v4/apis/${api_id}/swagger" \
    -H "Authorization: Bearer $admin_token" -H "accept: application/json" \
    -F "apiDefinition=${swagger_definition}")
if [[ $swagger_status -lt 200 || $swagger_status -ge 300 ]]; then
    echo "Failed to update AI API swagger. HTTP status: ${swagger_status}. Response:"
    cat "$swagger_response_file"
    exit 1
fi
rm -f "$swagger_response_file"

echo "Updating AI API endpoint security and resource auth"
api_details=$($curl_command -H "Authorization: Bearer $view_access_token" "${base_https_url}/api/am/publisher/v4/apis/${api_id}")
updated_api=$(echo "$api_details" | jq \
    --arg backend "$backend_endpoint_url" \
    --arg llm_provider_id "$llm_provider_id" \
    --argjson api_policies "$api_policies_json" \
    '.endpointConfig = {
        "endpoint_type":"http",
        "production_endpoints":{"url":$backend},
        "endpoint_security":{
          "production":{
            "enabled":true,
            "type":"apikey",
            "apiKeyIdentifier":"Authorization",
            "apiKeyValue":"",
            "apiKeyIdentifierType":"HEADER",
            "username":"",
            "password":null,
            "grantType":"",
            "tokenUrl":"",
            "clientId":null,
            "clientSecret":null,
            "secretKey":null,
            "accessKey":null,
            "service":null,
            "region":null,
            "uniqueIdentifier":null,
            "customParameters":{},
            "additionalProperties":{},
            "connectionTimeoutDuration":-1,
            "connectionRequestTimeoutDuration":-1,
            "socketTimeoutDuration":-1,
            "connectionTimeoutConfigType":"GLOBAL",
            "proxyConfigType":"GLOBAL",
            "proxyConfigs":{
              "proxyEnabled":false,
              "proxyHost":"",
              "proxyPort":"",
              "proxyUsername":"",
              "proxyPassword":"",
              "proxyProtocol":"",
              "proxyPasswordAlias":null
            }
          }
        }
      }
      | .operations = [{
          "target":"/v1/chat/completions",
          "verb":"POST",
          "authType":"Application & Application User",
          "throttlingPolicy":"Unlimited",
          "scopes":[],
          "operationPolicies":{"request":[],"response":[],"fault":[]}
        }]
      | .authorizationHeader = "Authorization"
      | .apiKeyHeader = "ApiKey"
      | .securityScheme = ["api_key","oauth_basic_auth_api_key_mandatory","oauth2"]
      | .apiPolicies = $api_policies
      | .subtypeConfiguration = {
          "subtype":"AIAPI",
          "configuration":("{\"llmProviderId\":\"" + $llm_provider_id + "\",\"llmProviderName\":\"MistralAI\",\"llmProviderApiVersion\":\"1.0.0\"}")
        }
      | .egress = true')

$curl_command -X PUT "${base_https_url}/api/am/publisher/v4/apis/${api_id}" \
    -H "Authorization: Bearer $admin_token" -H "Content-Type: application/json" -d "$updated_api" >/dev/null

echo "Creating and deploying AI API revision"
revision_response=$($curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/${api_id}/revisions" \
    -H "Authorization: Bearer $admin_token" -H "Content-Type: application/json" -d '{"description":"AI API performance test revision"}')
revision_id=$(echo "$revision_response" | jq -r '.id')
if [[ -z $revision_id || $revision_id == "null" ]]; then
    echo "Failed to create AI API revision. Response:"
    echo "$revision_response" | jq .
    exit 1
fi

$curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/${api_id}/deploy-revision?revisionId=${revision_id}" \
    -H "Authorization: Bearer $admin_token" -H "Content-Type: application/json" \
    -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' >/dev/null

echo "Publishing ${api_display_name}"
publish_status=$($curl_command -w "%{http_code}" -o /dev/null -H "Authorization: Bearer $publish_access_token" -X POST \
    "${base_https_url}/api/am/publisher/v4/apis/change-lifecycle?action=Publish&apiId=${api_id}")
if [[ $publish_status -ne 200 ]]; then
    echo "Failed to publish ${api_display_name}. HTTP status: ${publish_status}"
    exit 1
fi

echo "Subscribing ${api_display_name} to PerformanceTestAPP"
subscription_id=$($curl_command -H "Authorization: Bearer $sub_manage_token" -H "Content-Type: application/json" \
    -d "$(subscription_request "$api_id")" "${base_https_url}/api/am/devportal/v3/subscriptions" | jq -r '.subscriptionId')
if [[ -z $subscription_id || $subscription_id == "null" ]]; then
    echo "Failed to subscribe ${api_display_name} to PerformanceTestAPP."
    exit 1
fi

echo "Created AI API ${api_display_name} (${api_id}) at /${api_context}/${api_version}/v1/chat/completions"
