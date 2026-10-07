#!/bin/bash
# ==============================================================================
# Script Name: 03.events_operations_POST_delete.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes events using the `/events/operations` endpoint with
# operation=delete, and prints what became of each id.
#
# Usage:
# ./03.events_operations_POST_delete.sh EVENT_ID [EVENT_ID...]
#
#   EVENT_ID  the events to delete: required, as 01.events_GET.sh shows them
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Delete only events you know are stuck: it ends the server's tracking of the
#   event. The id is required, so that running the script bare deletes nothing.
# - Confirmed directly: the answer is 200 with a status for each id: "deleted", or
#   "not found". A "not found" does not make this script fail; read the lines.
# - Confirmed directly: no ids, or an empty list, answers 400 "Id is not specified."
# - Confirmed directly: any other operation (operation=purge) answers 200 with {} and
#   does nothing, so a misspelled operation looks like a success. This script only
#   sends operation=delete.
# - Requires `jq`, which builds the body and prints the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/events"
if [ "$#" -lt 1 ]; then
    printf "Usage: ./03.events_operations_POST_delete.sh EVENT_ID [EVENT_ID...]\n"
    exit 2
fi
BODY=$(jq -cn '{ids: $ARGS.positional}' --args "$@")

printf "Deleting %s event(s)...\n" "$#"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/operations?operation=delete" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '(.events // [])[] | "  \(.id): \(.status)"'
