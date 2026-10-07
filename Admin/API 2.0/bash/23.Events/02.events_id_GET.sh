#!/bin/bash
# ==============================================================================
# Script Name: 02.events_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one event using the `/events/{id}` endpoint: its status, the file
# it is for, the subscription and account it belongs to, and its data.
#
# Usage:
# ./02.events_id_GET.sh [EVENT_ID]
#
#   EVENT_ID  the event (default: the first one 01.events_GET.sh lists)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An event that is not there, or not visible to this administrator, answers 404
#   "Cannot find event with id ... or it is not accessible".
# - The id goes into the path URL-encoded once, with jq's @uri.
# - data and sessionData hold "key": "value" pairs the processing keeps.
# - Requires `jq`, which looks the id up, URL-encodes it and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/events"
EVENT_ID="$1"
if [ -z "${EVENT_ID}" ]; then
    EVENT_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" \
      -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -z "${EVENT_ID}" ]; then
        printf "There are no events to read.\n"
        exit 1
    fi
fi
ENCODED=$(jq -rn --arg id "${EVENT_ID}" '$id | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the event (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.status) \(.agentType) event for \(.fullTarget // "-")",
  "  account \(.accountName // "-"), subscription \(.subscriptionId // "-")",
  "  retries \(.retryCount), recovered \(.recovered), node \(.clusterNode // "-")"'
