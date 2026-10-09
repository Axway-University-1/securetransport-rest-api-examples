#!/bin/bash
# ==============================================================================
# Script Name: 04.transferProfiles_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves one transfer profile, using the `/transferProfiles/{id}` endpoint.
# The path takes the profile's id, so the script looks the id up by account and name first.
# It prints a short summary of the profile (with the advanced settings, when they are on), then only some fields of it.
#
# Usage:
# ./04.transferProfiles_id_GET.sh [ACCOUNT [NAME]]
#
#   ACCOUNT  the account the profile belongs to (default john, or ST_EXAMPLE_ACCOUNT)
#   NAME     the profile (default TP)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The profile is looked up by account and name, and must be the only one with that name.
# - Confirmed directly: an unknown id, well formed or not, is a JSON 404 "Transfer Profile with id X not found or not
#   accessible."; `fields=` keeps the keys named (`fields=name,sendMapping`) and an unknown field is 400. The profile
#   carries `advancedSettings` (transcoding of what is sent and of what is received, and `receiverMessage`) with every
#   default filled in; `enabled` false means the top level `transferMode`, `recordFormat`, `recordLength` and
#   `paddingStripEnabled` are the ones in force, and `enabled` true that the advanced `type`s of the two sides are (check 59). `metadata.links.account` is the only link.
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
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
ACCOUNT="${1:-${ST_EXAMPLE_ACCOUNT:-john}}"
NAME="${2:-TP}"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./04.transferProfiles_id_GET.sh [ACCOUNT [NAME]]\n"
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

# The one profile of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
st_get -G "${MAIN_URL}" --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name"
read -r FOUND PROFILE_ID < <(printf '%s\n' "${RESPONSE}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s transfer profiles named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

printf "The transfer profile %s of %s, id %s:\n" "${NAME}" "${ACCOUNT}" "${PROFILE_ID}"

st_get "${MAIN_URL}/${PROFILE_ID}"
PROFILE_JSON="${RESPONSE}"
if ! printf '%s' "${PROFILE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the transfer profile %s (id %s).\n" "${NAME}" "${PROFILE_ID}"
    exit 1
fi

printf '%s' "${PROFILE_JSON}" | jq -r '"  default:     \(.default)\n  send:        \(.sendMapping)\n  receive:     \(.receiveMapping)\n  file label:  \(.fileLabelOption)\n  mode:        \(.transferMode), \(.recordFormat) records of \(.recordLength)\n  acknowledge: \(.sendingAcknowledgmentEnabled)\n  advanced:    \(.advancedSettings.enabled)" + (if .advancedSettings.enabled then "\n  sending:     \(.advancedSettings.callerTranscoding.type), \(.advancedSettings.callerTranscoding.outputRecordFormat) records of \(.advancedSettings.callerTranscoding.outputRecordLength)\n  receiving:   \(.advancedSettings.receiverTranscoding.type), line ending \(.advancedSettings.receiverTranscoding.lineEndingFormat // "-")" else "" end)'

printf "\nOnly some fields of it:\n"
st_get -G "${MAIN_URL}/${PROFILE_ID}" --data-urlencode "fields=name,sendMapping,receiveMapping"
printf '%s' "${RESPONSE}"
printf "\n"
