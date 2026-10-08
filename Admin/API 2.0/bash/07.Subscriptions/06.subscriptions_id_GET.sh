#!/bin/bash
# ==============================================================================
# Script Name: 06.subscriptions_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one subscription, using the `/subscriptions/{id}` endpoint, and
# prints a short summary: the type, the folder, the pull sites and a few settings.
# The path takes the subscription's id, so the script looks the id up by account,
# application and folder first.
#
# Usage:
# ./06.subscriptions_id_GET.sh [ACCOUNT [APPLICATION [FOLDER]]]
#
#   ACCOUNT      the account that subscribes (default john)
#   APPLICATION  the application it subscribes to (default AdvancedRoutingApplication)
#   FOLDER       the folder of the subscription (default /inbox)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - Confirmed directly: an unknown id is a JSON 404, "Subscription with id X not found or not
#   accessible.". `fields=` keeps the keys named, and always `type`. `type=`, which the
#   reference says is needed to read a field of one subscription type, is not: `type=Basic` on an
#   Advanced Routing subscription answers the whole subscription.
# - The `type` of a subscription is the type of its application. A body that says another
#   type is accepted, and the application's type is used. What else is there depends on it: an
#   AdvancedRouting one has createFilesList, postClientDownloads, postProcessingActions and
#   postTransmissionActions; Basic, SharedFolder, SiteMailbox and StandardRouter have
#   postTransmissionActions; HumanSystem has `rules`; StandardRouter has `subscriberID`; MBFT has
#   only the common fields. Every field that is not set is null, not absent.
# - Confirmed directly: a subscription's folder is not made when the subscription is created. It
#   is in the account's home folder after the account's next login, or after the first pull.
# - Requires `jq`, which reads the id and prints the summary.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="${1:-john}"
APPLICATION="${2:-AdvancedRoutingApplication}"
FOLDER="${3:-/inbox}"
if [ "$#" -gt 3 ]; then
    printf "Usage: ./06.subscriptions_id_GET.sh [ACCOUNT [APPLICATION [FOLDER]]]\n"
    exit 2
fi

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

# The one subscription of that account on that application and folder: "1 <id>",
# or how many there are. The account and application filters are exact; the
# application and the folder are compared again here, on what comes back.
st_get -G "${MAIN_URL}" --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder"
read -r FOUND SUBSCRIPTION_ID < <(printf '%s\n' "${RESPONSE}" \
  | jq -r --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
    '[(.result // [])[] | select(.application == $application and .folder == $folder)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s subscriptions of the account %s on the application %s and the folder %s; this script acts on exactly one.\n" "${FOUND:-0}" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
    exit 1
fi

st_get "${MAIN_URL}/${SUBSCRIPTION_ID}"
SUBSCRIPTION_JSON="${RESPONSE}"
if ! printf '%s' "${SUBSCRIPTION_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the subscription %s.\n" "${SUBSCRIPTION_ID}"
    exit 1
fi
printf "The subscription of %s on %s, folder %s, id %s:\n" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}" "${SUBSCRIPTION_ID}"
printf '%s' "${SUBSCRIPTION_JSON}" | jq -r '"  type:              \(.type)",
  "  retention (days):  \(.fileRetentionPeriod // "-")",
  "  parallel pulls:    \(.maxParallelSitPulls // "-")",
  "  pull sites:        \([.transferConfigurations[]? | select(.outbound == false) | .site] | join(", ") | if . == "" then "-" else . end)",
  "  flow attributes:   \(.flowAttributes | length)"'

printf "\nOnly some of its fields, with fields=id,folder,fileRetentionPeriod:\n"
st_get -G "${MAIN_URL}/${SUBSCRIPTION_ID}" --data-urlencode "fields=id,folder,fileRetentionPeriod"
printf '%s\n' "${RESPONSE}" | jq -c .
