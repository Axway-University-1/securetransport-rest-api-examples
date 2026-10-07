#!/bin/bash
# ==============================================================================
# Script Name: 02.logs_audit_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one audit log entry using the `/logs/audit/{id}` endpoint: the change, who
# made it, from where, and a text of the object as it was.
#
# Usage:
# ./02.logs_audit_id_GET.sh [ID]
#
#   ID  the entry's id (default: the newest entry)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The id is a plain string, unlike the composite ids of the transfer and server logs.
# - objectString is the audited object written out, which can be long; for a created or changed
#   object it shows the values it was given.
# - A missing id answers 404 "Audit log entry with Id ... not found".
# - Requires `jq`, which looks the newest entry up and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/audit"
ENTRY_ID="$1"
if [ -z "${ENTRY_ID}" ]; then
    ENTRY_ID=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -z "${ENTRY_ID}" ]; then
        printf "The audit log is empty.\n"
        exit 1
    fi
fi
ENCODED=$(jq -rn --arg id "${ENTRY_ID}" '$id | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the entry (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.operationType) \(.objectType) \(.objectName // "-"), \(.dateModified)",
  "  by \(.userName // "-") from \(.remoteAddress // "-") (\(.userAgent // "no user agent"))",
  "  \(.description // "no description")"'
