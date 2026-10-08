#!/bin/bash
# ==============================================================================
# Script Name: 09.subscriptions_id_operations_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script pulls files into a subscription's folder on demand, using the
# `/subscriptions/{id}/operations` endpoint with operation=Pull. The pull uses a
# transfer site of the subscription; the files it matches are downloaded into the
# subscription's folder, where the routes of the subscription see them.
#
# Usage:
# ./09.subscriptions_id_operations_POST_pull.sh ACCOUNT APPLICATION FOLDER [SITE]
#
#   ACCOUNT      the account that subscribes
#   APPLICATION  the application it subscribes to
#   FOLDER       the folder of the subscription
#   SITE         the transfer site to pull with (default: the site of the subscription's
#                own PARTNER-IN transfer configuration)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - 02.subscriptions_POST.sh creates a subscription with a pull site. The site is read from the
#   subscription, so the subscription must have a transfer configuration, or SITE must be given.
# - The pull runs on in the background: 202 means it was accepted. The script prints the
#   operationIndex of the answer's link; follow it with 16.TransferLogs/01.logs_transfers_GET.sh.
# - Confirmed directly: a file pulled lands in the subscription's folder within seconds and stays on
#   the partner (the pull copies). The body is needed: with none the answer is a 403 "The server was
#   unable to comply with your request"; `{"type":"pull"}` on a subscription with no transfer
#   configuration is 400 "No transfer configuration found for this subscription."; a site that does
#   not exist is 406 "Site 'X' was not found."; a wrong `type` is 400 with a misleading
#   "Unsupported parameter - site". `fileRetentionPeriod` (0 to 36500, else 400) in the body is the
#   retention for this pull. When the subscription keeps a pull history (its fileRetentionPeriod is
#   more than 0, which needs an SFTP site), a file already pulled is not pulled again, even after it
#   was deleted from the folder, until 10.subscriptions_id_operations_POST_clearPullHistory.sh.
#   `createFilesListEnabled` and `createFilesListFilename` in the body make this pull write a file
#   that lists the files it pulled. The operation name is case sensitive (`pull` is 404).
# - Requires `jq`, which reads the id and the site, and builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="$1"
APPLICATION="$2"
FOLDER="$3"
[ -n "${ACCOUNT}" ] && [ -n "${APPLICATION}" ] && [ -n "${FOLDER}" ] || { printf "Usage: ./09.subscriptions_id_operations_POST_pull.sh ACCOUNT APPLICATION FOLDER [SITE]\n"; exit 2; }
SITE="$4"

# The one subscription of that account on that application and folder: "1 <id>",
# or how many there are. The account and application filters are exact; the
# application and the folder are compared again here, on what comes back.
read -r FOUND SUBSCRIPTION_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
    '[(.result // [])[] | select(.application == $application and .folder == $folder)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s subscriptions of the account %s on the application %s and the folder %s; this script acts on exactly one.\n" "${FOUND:-0}" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
    exit 1
fi

SUBSCRIPTION_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SUBSCRIPTION_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SUBSCRIPTION_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the subscription %s.\n" "${SUBSCRIPTION_ID}"
    exit 1
fi
if [ -z "${SITE}" ]; then
    SITE=$(printf '%s' "${SUBSCRIPTION_JSON}" | jq -r '[.transferConfigurations[]? | select(.outbound == false) | .site][0] // empty')
fi
if [ -z "${SITE}" ]; then
    printf "The subscription has no pull site (no PARTNER-IN transfer configuration); give one as the fourth argument.\n"
    exit 1
fi
BODY=$(jq -n --arg site "${SITE}" '{type: "pull", site: $site}')

printf "Pulling into the folder '%s' of '%s' with the site '%s'...\n" "${FOLDER}" "${ACCOUNT}" "${SITE}"
RESPONSE=$(curl -s -w "\n%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${SUBSCRIPTION_ID}/operations?operation=Pull" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
HTTP_CODE=${RESPONSE##*$'\n'}
RESULT=${RESPONSE%$'\n'*}
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" = "202" ]; then
    printf '%s' "${RESULT}" | jq -r '.message, ("operationIndex: " + (.link | capture("operationIndex=(?<i>[^&]+)").i))'
else
    printf "%s\n" "${RESULT}"
    exit 1
fi
