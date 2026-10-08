#!/bin/bash
# ==============================================================================
# Script Name: 02.routes_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# Composite Routes are a type of route that allows you to inherit a Route
# Template and extend it with additional routes if needed.
#
# This script shows how to create a composite route using the `/routes`
# endpoint. It demonstrates:
# - Looking up the ID of an existing route template by name
# - Creating a composite route that inherits a template without extending it
# - Creating a simple route and reading its new ID from the Location header
# - Creating a composite route that inherits a template and extends it with
#   that simple route, through an ExecuteRoute step
#
# Usage:
# ./02.routes_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The route template must already exist. Run 08.RouteTemplates first.
# - The account "john" must already exist.
# - Requires `jq`, which reads the route template ID out of the response.
# - Every call is checked: the template lookup must answer 200, each creation 201 (the status is printed); anything else prints
#   the status and the server's answer and ends the script with exit 1. The bodies are built by jq.
# - Exit codes: 0 when all three routes were created, 1 otherwise.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
printf "Loading variables into our context...\n\n"
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"
ACCOUNT="john"

# The response headers of each creation go to a temporary file
HEADERS=$(mktemp)
trap 'rm -f "${HEADERS}"' EXIT

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

# st_post_route BODY: POST the body to /routes. The answer is left in RESPONSE and the headers (the Location of the
# new route) in HEADERS. Prints the status; any status but 201 ends the script with exit 1, after the server's answer.
st_post_route() {
    RESPONSE=$(curl -s -D "${HEADERS}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "$1" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}


# Composite Routes are a type of route that allows you to inherit a Route Template and extend it with additional routes if needed.
# The following example shows how to create a composite route in SecureTransport using the API.
# The first route will inherit a route template without extending it.
# The second route will inherit a route template and extend it with additional routes.


# First, get the ID of the Route Template we need
# Requires `jq`, which reads the id out of the response reliably.
ROUTE_TEMPLATE_NAME="RouteFromAccountant"
st_get "${MAIN_URL}?fields=id&name=${ROUTE_TEMPLATE_NAME}"
ROUTE_TEMPLATE_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result[0].id // empty')

if [ -z "${ROUTE_TEMPLATE_ID}" ]; then
    echo "Error: Could not retrieve Route Template ID for '${ROUTE_TEMPLATE_NAME}'. Please check if the route template exists."
    exit 1
fi
printf "Route Template ID for '%s': %s\n\n" "${ROUTE_TEMPLATE_NAME}" "${ROUTE_TEMPLATE_ID}"



# ===========================================================================================
# Example 1 without extension.
# Simple POST to create a package route in SecureTransport
printf "Creating a composite route without extension...\n\n"
BODY=$(jq -cn --arg account "${ACCOUNT}" --arg template "${ROUTE_TEMPLATE_ID}" \
  '{account: $account, name: "CompositeRoute_WithoutExtension", type: "COMPOSITE", conditionType: "MATCH_ALL", routeTemplate: $template}')
st_post_route "${BODY}"


# ===========================================================================================
# Example 2 with extension
# To create a composite route with an extension, we will first create a simple route that will be used as an extension.
printf "Creating a simple route...\n\n"
BODY=$(jq -cn '{name: "SimpleRouteName", type: "SIMPLE", conditionType: "ALWAYS",
  steps: [{type: "EncodingConversion", status: "ENABLED", conditionType: "ALWAYS", usePrecedingStepFiles: false,
           fileFilterExpression: "string", fileFilterExpressionType: "GLOB", inputCharset: "UTF-8", outputCharset: "UTF-8",
           postTransformationActionRenameAsExpression: "string", actionOnStepFailure: "PROCEED"}]}')
st_post_route "${BODY}"

LOCATION=$(grep -i '^Location:' "${HEADERS}" | awk '{print $2}' | tr -d '\r')
if [ -z "${LOCATION}" ]; then
    echo "Error: Could not read the Location header of the new simple route."
    exit 1
fi
echo "Resource created at: $LOCATION"

# Extract the ID from the Location URL
SIMPLE_ROUTE_ID=$(basename "$LOCATION")
echo "New resource ID: $SIMPLE_ROUTE_ID"


printf "Creating a composite route with extension...\n\n"
BODY=$(jq -cn --arg account "${ACCOUNT}" --arg template "${ROUTE_TEMPLATE_ID}" --arg simple "${SIMPLE_ROUTE_ID}" \
  '{account: $account, name: "CompositeRoute_WithExtension", type: "COMPOSITE", conditionType: "MATCH_ALL", routeTemplate: $template,
    steps: [{type: "ExecuteRoute", status: "ENABLED", executeRoute: $simple, autostart: false}]}')
st_post_route "${BODY}"
