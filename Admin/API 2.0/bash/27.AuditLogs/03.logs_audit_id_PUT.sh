#!/bin/bash
# ==============================================================================
# Script Name: 03.logs_audit_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script tries to change the description of an audit log entry using the
# `/logs/audit/{id}` endpoint with PUT, and reads the entry back to show what happened.
#
# Usage:
# ./03.logs_audit_id_PUT.sh ID [DESCRIPTION]
#
#   ID           the entry's id (see 01.logs_audit_GET.sh, 02.logs_audit_id_GET.sh)
#   DESCRIPTION  the text to try (default "Changed by 03.logs_audit_id_PUT.sh")
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the server ANSWERS 204, as for a change, but the description stays what
#   it was: on entries of every kind, for old ones and new, with the whole entry sent back or
#   only the required fields. The audit trail cannot be edited through this call. This script
#   prints the description before and after, so that it is plain.
# - The body needs id, configurationId, operationType and dateModified; this script sends back
#   what it read, with the new description. A body without them answers 400 "must not be null".
# - The id is required, though nothing is changed.
# - Requires `jq`, which URL-encodes the id and edits the entry.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/audit"
ENTRY_ID="$1"
DESCRIPTION="${2:-Changed by 03.logs_audit_id_PUT.sh}"
if [ -z "${ENTRY_ID}" ]; then
    printf "Usage: ./03.logs_audit_id_PUT.sh ID [DESCRIPTION]\n"
    exit 2
fi
ENCODED=$(jq -rn --arg id "${ENTRY_ID}" '$id | @uri')

ENTRY=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${ENTRY}" | jq -e '.operationType' >/dev/null 2>&1; then
    printf "There is no audit log entry %s.\n" "${ENTRY_ID}"
    exit 1
fi
BEFORE=$(printf '%s' "${ENTRY}" | jq -r '.description // ""')
printf "The description is now: %s\n" "${BEFORE}"
BODY=$(printf '%s' "${ENTRY}" | jq -c --arg description "${DESCRIPTION}" 'del(.metadata) | .description = $description')

printf "Trying to set it to: %s\n" "${DESCRIPTION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi

AFTER=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.description // ""')
printf "The description is now: %s\n" "${AFTER}"
if [ "${AFTER}" = "${BEFORE}" ] && [ "${DESCRIPTION}" != "${BEFORE}" ]; then
    printf "It did not change: the audit log cannot be edited.\n"
fi
