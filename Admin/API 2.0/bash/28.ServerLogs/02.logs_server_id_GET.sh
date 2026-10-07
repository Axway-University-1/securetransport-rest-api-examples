#!/bin/bash
# ==============================================================================
# Script Name: 02.logs_server_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one server log entry using the `/logs/server/{id}` endpoint: the message in
# full, with the thread, the class and line that wrote it, and a stack trace if there is one.
#
# Usage:
# ./02.logs_server_id_GET.sh [ID]
#
#   ID  the entry's id, as 01.logs_server_GET.sh could show it under id.urlrepresentation
#       (default: the newest entry)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The id is the urlrepresentation of the id object: Base64 of "Id [mConfigurationId=...,
#   mEventId=..., mTimestamp=...]". An id that is not Base64 of that form answers 400 "Invalid
#   format for log entry ID"; a well formed one that is not there answers 404.
# - The newest entry is found by asking for the last one: the log is oldest first.
# - Requires `jq`, which finds the newest entry and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/server"
ENTRY_ID="$1"
if [ -z "${ENTRY_ID}" ]; then
    TOTAL=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.resultSet.totalCount // 0')
    ENTRY_ID=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" --data-urlencode "limit=1" --data-urlencode "offset=$(( TOTAL > 0 ? TOTAL - 1 : 0 ))" \
      --data-urlencode "fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id.urlrepresentation // empty')
    if [ -z "${ENTRY_ID}" ]; then
        printf "The server log is empty.\n"
        exit 1
    fi
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENTRY_ID}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
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
  "  \(.time)  \(.level)  \(.component)  thread \(.thread // "-")",
  "  \((.message // "") | gsub("[\n\t]"; " ") | .[0:200])",
  "  written by \(.className // "-").\(.method // "-") line \(.line // "-")"'
