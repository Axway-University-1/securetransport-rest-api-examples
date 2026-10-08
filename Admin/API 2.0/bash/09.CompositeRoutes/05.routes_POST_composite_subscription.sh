#!/bin/bash
# ==============================================================================
# Script Name: 05.routes_POST_composite_subscription.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a composite route that is linked to a subscription, using
# the `/routes` endpoint. Linked this way, the route runs on every file that
# arrives in the subscription's folder. It demonstrates:
# - Looking up three ids by name: the route template, the subscription and the
#   simple route to run
# - Creating a composite route that inherits the template, lists the
#   subscription, and runs the simple route through an ExecuteRoute step
#
# Usage:
# ./05.routes_POST_composite_subscription.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Run these first:
#     08.RouteTemplates/02.routes_POST.sh               the template RouteFromPartner
#     07.Subscriptions/02.subscriptions_POST.sh         john's subscription on /inbox
#     09.CompositeRoutes/03.routes_POST_simple_compress.sh   SimpleRoute_Compress
# - It uses a different template than 02.routes_POST.sh, so the two do not
#   touch each other's routes.
# - Requires `jq`, which reads the ids out of the responses and builds the body.
# - Every call is checked: the three lookups must answer 200, and the creation 201 (the status is printed); anything else prints
#   the status and the server's answer and ends the script with exit 1.
# - Exit codes: 0 when the route was created, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

ACCOUNT="john"
ROUTE_NAME="CompositeRoute_Subscription"
ROUTE_TEMPLATE_NAME="RouteFromPartner"
SUBSCRIPTION_FOLDER="/inbox"
SIMPLE_ROUTE_NAME="SimpleRoute_Compress"

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

st_get "${MAIN_URL}/routes?fields=id&name=${ROUTE_TEMPLATE_NAME}"
ROUTE_TEMPLATE_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result[0].id // empty')
if [ -z "${ROUTE_TEMPLATE_ID}" ]; then
    printf "Could not find the route template '%s'. Run 08.RouteTemplates first.\n" "${ROUTE_TEMPLATE_NAME}"
    exit 1
fi

st_get "${MAIN_URL}/subscriptions?account=${ACCOUNT}"
SUBSCRIPTION_ID=$(printf '%s\n' "${RESPONSE}" \
  | jq -r --arg folder "${SUBSCRIPTION_FOLDER}" '[(.result // [])[] | select(.folder == $folder)][0].id // empty')
if [ -z "${SUBSCRIPTION_ID}" ]; then
    printf "Could not find a subscription of '%s' on '%s'. Run 07.Subscriptions first.\n" "${ACCOUNT}" "${SUBSCRIPTION_FOLDER}"
    exit 1
fi

st_get "${MAIN_URL}/routes?fields=id&name=${SIMPLE_ROUTE_NAME}"
SIMPLE_ROUTE_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result[0].id // empty')
if [ -z "${SIMPLE_ROUTE_ID}" ]; then
    printf "Could not find the simple route '%s'. Run 03.routes_POST_simple_compress.sh first.\n" "${SIMPLE_ROUTE_NAME}"
    exit 1
fi

printf "Template %s, subscription %s, simple route %s\n" "${ROUTE_TEMPLATE_ID}" "${SUBSCRIPTION_ID}" "${SIMPLE_ROUTE_ID}"

BODY=$(jq -n --arg account "${ACCOUNT}" --arg name "${ROUTE_NAME}" \
  --arg template "${ROUTE_TEMPLATE_ID}" --arg subscription "${SUBSCRIPTION_ID}" --arg simple "${SIMPLE_ROUTE_ID}" \
  '{type: "COMPOSITE", account: $account, name: $name, conditionType: "MATCH_ALL",
    routeTemplate: $template, subscriptions: [$subscription],
    steps: [{type: "ExecuteRoute", status: "ENABLED", autostart: false, executeRoute: $simple}]}')

printf "Creating the composite route '%s'...\n" "${ROUTE_NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/routes" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
