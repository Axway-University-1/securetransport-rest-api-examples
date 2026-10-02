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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The route template must already exist. Run 08.RouteTemplates first.
# - The account "john" must already exist.
# - Requires `jq`, which reads the route template ID out of the response.
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


# Composite Routes are a type of route that allows you to inherit a Route Template and extend it with additional routes if needed.
# The following example shows how to create a composite route in SecureTransport using the API.
# The first route will inherit a route template without extending it.
# The second route will inherit a route template and extend it with additional routes.


# First, get the ID of the Route Template we need
# Requires `jq`, which reads the id out of the response reliably.
ROUTE_TEMPLATE_NAME="RouteFromAccountant"
ROUTE_TEMPLATE_ID=$(curl --silent --show-error -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes?fields=id&name=${ROUTE_TEMPLATE_NAME}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')

if [ -z "${ROUTE_TEMPLATE_ID}" ]; then
    echo "Error: Could not retrieve Route Template ID for '${ROUTE_TEMPLATE_NAME}'. Please check if the route template exists."
    exit 1
fi
printf "Route Template ID for '%s': %s\n\n" "${ROUTE_TEMPLATE_NAME}" "${ROUTE_TEMPLATE_ID}"



# ===========================================================================================
# Example 1 without extension.
# Simple POST to create a package route in SecureTransport
printf "Creating a composite route without extension...\n\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "{
   \"account\" : \"john\",
   \"name\" : \"CompositeRoute_WithoutExtension\",
   \"type\": \"COMPOSITE\",
   \"conditionType\": \"MATCH_ALL\",
   \"routeTemplate\": \"${ROUTE_TEMPLATE_ID}\"
}"


# ===========================================================================================
# Example 2 with extension
# To create a composite route with an extension, we will first create a simple route that will be used as an extension.
printf "Creating a simple route...\n\n"

# Create a temporary file to store the response headers
response_headers=$(mktemp)

curl -s -D "$response_headers" -o /dev/null -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "{
  \"name\": \"SimpleRouteName\",
  \"type\": \"SIMPLE\",
  \"conditionType\": \"ALWAYS\",
  \"steps\": [{
      \"type\": \"EncodingConversion\",
      \"status\": \"ENABLED\",
      \"conditionType\": \"ALWAYS\",
      \"usePrecedingStepFiles\": false,
      \"fileFilterExpression\": \"string\",
      \"fileFilterExpressionType\": \"GLOB\",
      \"inputCharset\": \"UTF-8\",
      \"outputCharset\": \"UTF-8\",
      \"postTransformationActionRenameAsExpression\": \"string\",
       \"actionOnStepFailure\" : \"PROCEED\"
    }]
}"

LOCATION=$(grep -i '^Location:' "$response_headers" | awk '{print $2}' | tr -d '\r')
echo "Resource created at: $LOCATION"

# Extract the ID from the Location URL
SIMPLE_ROUTE_ID=$(basename "$LOCATION")
echo "New resource ID: $SIMPLE_ROUTE_ID"

rm "$response_headers"


printf "Creating a composite route with extension...\n\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "{
   \"account\" : \"john\",
   \"name\" : \"CompositeRoute_WithExtension\",
   \"type\": \"COMPOSITE\",
   \"conditionType\": \"MATCH_ALL\",
   \"routeTemplate\": \"${ROUTE_TEMPLATE_ID}\",
   \"steps\": [{
        \"type\": \"ExecuteRoute\",
        \"status\": \"ENABLED\",
        \"executeRoute\": \"${SIMPLE_ROUTE_ID}\",
        \"autostart\": false}]
}"

