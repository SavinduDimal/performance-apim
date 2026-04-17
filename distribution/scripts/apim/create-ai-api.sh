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

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -a <apim_host> -n <api_name> -b <backend_endpoint_url> [-d <api_description>] [-f <openapi_file>] [-h]"
    echo ""
    echo "-a: Hostname of WSO2 API Manager."
    echo "-n: API context/name prefix. The API name will be <api_name>API."
    echo "-b: Mock AI backend endpoint URL."
    echo "-d: API Description."
    echo "-f: OpenAPI file to import. Default: $openapi_file"
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "a:n:d:b:f:h" opt; do
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

if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq."
    exit 1
fi

base_https_url="https://${apim_host}:9443"
api_display_name="${api_name}API"
api_context="${api_name}"
curl_command="curl -sk"

echo "Fetching MistralAI LLM provider ID"
llm_provider_id=$($curl_command "${base_https_url}/api/am/publisher/v4/ai-service-providers" \
    -u "${auth}" -H "accept: application/json" \
    | jq -r '.list[] | select(.name=="MistralAI" and .deprecated==false) | .id')

if [[ -z $llm_provider_id || $llm_provider_id == "null" ]]; then
    echo "Could not find the MistralAI LLM provider."
    exit 1
fi

existing_api_id=$($curl_command -u "${auth}" \
    "${base_https_url}/api/am/publisher/v4/apis?query=name:${api_display_name}\$" | jq -r '.list[0] | .id')

if [[ -n $existing_api_id && $existing_api_id != "null" ]]; then
    echo "Deleting existing ${api_display_name} API with ID ${existing_api_id}"
    $curl_command -w "%{http_code}" -o /dev/null -u "${auth}" -X DELETE \
        "${base_https_url}/api/am/publisher/v4/apis/${existing_api_id}"
fi

echo "Importing OpenAPI definition for ${api_display_name} from ${openapi_file}"
create_response=$($curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/import-openapi" \
    -u "${auth}" \
    -H "accept: application/json" \
    -F "inlineAPIDefinition=<${openapi_file}" \
    -F 'additionalProperties={"name":"'"${api_display_name}"'","version":"'"${api_version}"'","context":"'"${api_context}"'","gatewayType":"wso2/synapse","policies":["Unlimited"],"subtypeConfiguration":{"subtype":"AIAPI","configuration":{"llmProviderId":"'"${llm_provider_id}"'"}},"securityScheme":["api_key"],"egress":true,"endpointConfig":{"endpoint_type":"http","production_endpoints":{"url":"'"${backend_endpoint_url}"'"}}}')

api_id=$(echo "$create_response" | jq -r '.id')
if [[ -z $api_id || $api_id == "null" ]]; then
    echo "Failed to create AI API. Response:"
    echo "$create_response" | jq .
    exit 1
fi

echo "Updating AI API endpoint security and resource auth"
api_details=$($curl_command -u "${auth}" "${base_https_url}/api/am/publisher/v4/apis/${api_id}")
updated_api=$(echo "$api_details" | jq \
    --arg backend "$backend_endpoint_url" \
    --arg llm_provider_id "$llm_provider_id" \
    '.endpointConfig = {
        "endpoint_type":"http",
        "production_endpoints":{"url":$backend},
        "endpoint_security":{
          "production":{
            "enabled":true,
            "type":"apikey",
            "apiKeyIdentifier":"Authorization",
            "apiKeyValue":"Bearer abc",
            "apiKeyIdentifierType":"HEADER",
            "username":"",
            "password":null,
            "grantType":"",
            "tokenUrl":"",
            "clientId":null,
            "clientSecret":null,
            "customParameters":{},
            "connectionTimeoutDuration":-1,
            "connectionRequestTimeoutDuration":-1,
            "socketTimeoutDuration":-1,
            "connectionTimeoutConfigType":"GLOBAL",
            "proxyConfigType":"GLOBAL",
            "proxyConfigs":{
              "proxyEnabled":"",
              "proxyHost":"",
              "proxyPort":"",
              "proxyUsername":"",
              "proxyPassword":"",
              "proxyProtocol":""
            }
          }
        }
      }
      | .operations = [{
          "target":"/v1/chat/completions",
          "verb":"POST",
          "authType":"None",
          "throttlingPolicy":"Unlimited",
          "scopes":[],
          "operationPolicies":{"request":[],"response":[],"fault":[]}
        }]
      | .securityScheme = ["api_key"]
      | .subtypeConfiguration = {
          "subtype":"AIAPI",
          "configuration":("{\"llmProviderId\":\"" + $llm_provider_id + "\",\"llmProviderName\":\"MistralAI\",\"llmProviderApiVersion\":\"1.0.0\"}")
        }
      | .egress = true')

$curl_command -X PUT "${base_https_url}/api/am/publisher/v4/apis/${api_id}" \
    -u "${auth}" -H "Content-Type: application/json" -d "$updated_api" >/dev/null

echo "Creating and deploying AI API revision"
revision_response=$($curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/${api_id}/revisions" \
    -u "${auth}" -H "Content-Type: application/json" -d '{"description":"AI API performance test revision"}')
revision_id=$(echo "$revision_response" | jq -r '.id')
if [[ -z $revision_id || $revision_id == "null" ]]; then
    echo "Failed to create AI API revision. Response:"
    echo "$revision_response" | jq .
    exit 1
fi

$curl_command -X POST "${base_https_url}/api/am/publisher/v4/apis/${api_id}/deploy-revision?revisionId=${revision_id}" \
    -u "${auth}" -H "Content-Type: application/json" \
    -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' >/dev/null

echo "Publishing ${api_display_name}"
publish_status=$($curl_command -w "%{http_code}" -o /dev/null -u "${auth}" -X POST \
    "${base_https_url}/api/am/publisher/v4/apis/change-lifecycle?action=Publish&apiId=${api_id}")
if [[ $publish_status -ne 200 ]]; then
    echo "Failed to publish ${api_display_name}. HTTP status: ${publish_status}"
    exit 1
fi

echo "Created AI API ${api_display_name} (${api_id}) at /${api_context}/${api_version}/v1/chat/completions"
