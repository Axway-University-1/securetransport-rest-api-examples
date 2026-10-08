#!/bin/bash
# ==============================================================================
# Script Name: 01.transactionManager_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the status of the Transaction Manager (TM), the component that runs the server's
# file transfers and routing events, using the `/transactionManager` endpoint.
# It demonstrates:
# - Reading the status text the server gives
# - Telling a running Transaction Manager from one that is stopped or stopping, by the exit code
#
# Usage:
# ./01.transactionManager_GET.sh
#
#   Exit code: 0 when the Transaction Manager is running, 1 when the server refuses or it is not running.
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which reads the status from the answer.
# - The answer is one object with one field, `status`, a free text: the reference says only "running, stopped or shutdown is in progress".
# - Confirmed directly: a running Transaction Manager answers 200 `{"status": "Running."}` (with a full stop). The script
#   decides on the word "Running", the way `python/python3/stGraceful.py` does, and not on the whole text. What the stopped or the
#   stopping answers read was NOT SEEN: stopping the Transaction Manager cannot be undone through the API (see 02), so the lab
#   was never stopped. The reference lists them without giving the words.
# - Confirmed directly: `fields=` is ignored (even an unknown one); HEAD is 200; PUT, PATCH and DELETE are 405 "HTTP 405 Method Not
#   Allowed"; `Accept: application/xml` and `text/csv` are 406; `/transactionManager/x` is 404.
# - Used before the stop in 02, to see that there is something to stop.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transactionManager"
printf "Reading the status of the Transaction Manager...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
STATUS=$(printf '%s' "${RESPONSE}" | jq -r '.status // "unknown"')
printf "Transaction Manager status: %s\n" "${STATUS}"
case "${STATUS}" in
    *Running*) ;;
    *) exit 1 ;;
esac
