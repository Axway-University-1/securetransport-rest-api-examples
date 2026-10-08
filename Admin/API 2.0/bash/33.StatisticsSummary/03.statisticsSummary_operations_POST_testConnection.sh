#!/bin/bash
# ==============================================================================
# Script Name: 03.statisticsSummary_operations_POST_testConnection.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script tests the connection to the Amplify Platform, where the usage report is sent, using the
# `/statisticsSummary/operations` endpoint with operation=testConnection: the server asks the platform for a token
# with the client id and secret, and says whether it worked. Nothing is saved: the settings in use do not change.
# It demonstrates:
# - Testing the credentials saved on the server (the StatisticsSummaryReport options), by giving none
# - Testing other credentials, the secret read from the environment
#
# Usage:
# ./03.statisticsSummary_operations_POST_testConnection.sh [CLIENT_ID [NETWORK_ZONE [ENV_ID]]]
#
#   CLIENT_ID     test this client id (optional; the saved one is used when left out)
#   NETWORK_ZONE  go through this network zone (optional)
#   ENV_ID        the environment id (optional)
#
#   The client secret is read from the environment, never from an argument:
#     export AMPLIFY_CLIENT_SECRET='the secret'
#
# Risk: read - the server connects to the Amplify Platform; nothing is saved
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which builds the body and reads the answer.
# - The body is JSON: `type` (must be testConnection) and, when given, `clientId`, `clientSecret`, `networkZone` and `envId`.
#   Whatever is left out is taken from the server's own StatisticsSummaryReport options (ClientId, ClientSecret, NetworkZone,
#   EnvironmentId, Platform.Authentication, Platform.API). They are set by 13.Configurations/02.configurations_PATCH_UsageReporting.sh.
#   With no argument and no secret this tests the saved credentials, and SENDS THE SAVED SECRET to the platform's login address.
# - Confirmed directly: the server really connects. It POSTs `grant_type=client_credentials&client_id=...&client_secret=...` as a
#   form to `StatisticsSummaryReport.Platform.Authentication` (a stand-in at that address saw it, with the ids given in the body, or
#   the saved ones), then, with the token, calls `Platform.API`. The lab reaches the real platform: placeholder credentials get back
#   `{"error":"invalid_client","error_description":"Invalid client or Invalid client credentials","code":401}`.
# - Confirmed directly: **a refusal by the platform is relayed with the platform's own status and body**: the 401 above is the
#   platform's, not your administrator login being refused, and a 500 from the token address came back as 500 with its own body
#   (`{"error":"boom","code":500}`); this script prints the platform's `error` and `error_description` for those. A token
#   that the platform's API does not accept (a stand-in handed out `fake`) is 401 `{"code":401,"description":"Invalid access token"}`.
# - Confirmed directly: **a failure the server finds itself is 406** (not 400) with `validationErrors`: "Test connection to the
#   Amplify Platform failed. Please check if the StatisticsSummaryReport.Platform.* server configuration options are set correctly or
#   re-enter your client secret and try again.". That is what a body with no `type` (even `{}`), a `type` that is not exactly testConnection
#   (`nope`, `TESTCONNECTION`), or a `networkZone` that is not empty gets: in each case with no call to the token address first.
#   The server sends nothing to a zone given; one that does not exist is a failure.
# - Confirmed directly: `clientId` and `clientSecret` may be given one without the other (the other is the saved one). With a `type` that is wrong or missing
#   AND a `clientId` or `clientSecret` the answer is 400 "Unsupported parameter - clientId", not 406. A missing `operation` is 400
#   "Invalid operation. Valid operation is: testConnection.", but `operation=nope` and `operation=TestConnection` still ran the
#   test: the value is not checked, only that there is one. GET and HEAD are 405.
# - NOT SEEN: a connection that works. That needs a real client id and secret from the platform (a stand-in token address is not
#   enough: the server then calls `Platform.API`, which must be HTTPS and reachable). The reference gives the answer as `{"message": ...}`
#   with 200 or 202, and this script prints the message and exits 0 for either.
# - Exit codes: 0 when the server answered 200 or 202, 1 when it refuses or the test fails.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/operations"
CLIENT_ID="$1"
NETWORK_ZONE="$2"
ENV_ID="$3"
if [ -n "$4" ]; then
    printf "Usage: 03.statisticsSummary_operations_POST_testConnection.sh [CLIENT_ID [NETWORK_ZONE [ENV_ID]]]\n"
    exit 2
fi

BODY=$(jq -cn --arg id "${CLIENT_ID}" --arg secret "${AMPLIFY_CLIENT_SECRET}" --arg zone "${NETWORK_ZONE}" --arg env "${ENV_ID}" '
  {type: "testConnection"}
  + (if $id != "" then {clientId: $id} else {} end)
  + (if $secret != "" then {clientSecret: $secret} else {} end)
  + (if $zone != "" then {networkZone: $zone} else {} end)
  + (if $env != "" then {envId: $env} else {} end)')

if [ -n "${CLIENT_ID}" ]; then
    printf "Testing the connection to the Amplify Platform as client %s...\n" "${CLIENT_ID}"
else
    printf "Testing the connection to the Amplify Platform with the saved settings...\n"
fi
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}?operation=testConnection" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    200|202)
        printf '%s' "${RESPONSE}" | jq -r '.message // .'
        ;;
    *)
        printf '%s' "${RESPONSE}" | jq -r 'if .error then "The platform answered: \(.error): \(.error_description // "")" else (.validationErrors[0] // .description // .message // .) end' 2>/dev/null
        exit 1
        ;;
esac
