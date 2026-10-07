#!/bin/bash
# ==============================================================================
# Script Name: 04.logs_transfers_id_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script performs an operation on one transfer using the
# `/logs/transfers/{id}/operations` endpoint: cancel it, resubmit it, verify its receipt, or
# acknowledge it.
#
# Usage:
# ./04.logs_transfers_id_operations_POST.sh ID OPERATION [MESSAGE]
#
#   ID         the transfer's id (see 03.logs_transfers_id_GET.sh)
#   OPERATION  cancel, resubmit, verify, ack or nack
#   MESSAGE    for ack and nack only: the message to send (optional)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The id is required: these operations act on a real transfer.
# - Confirmed directly, on a transfer that had finished: resubmit answers 200 "was
#   successfully resubmitted". cancel answers 400 "is not eligible for cancellation"; verify
#   400 "does not have a receipts"; ack and nack 400 "protocol http does not support
#   acknowledgements", since only a received PeSIT transfer can be acknowledged.
# - Confirmed directly: cancel is refused for a transfer that is still In Progress: a 10 MB upload
#   over FTP, a 10 MB upload through the EndUser API, a 10 MB pull over SSH, each kept running
#   for 40 seconds, and a route's send to a partner; resubmit then answers 400 "cannot be
#   resubmitted". The server says so itself: isCancelable is false (03.logs_transfers_id_GET.sh).
# - Confirmed directly: what can be cancelled is a transfer waiting to be retried: a PeSIT pull
#   that failed (the sender had no such file) and is counted as "to retry" by
#   05.logs_transfers_pullSummary_GET.sh. Cancel answers 200 "was successfully cancelled", the
#   count moves from retry to failed, isCancelable turns false, and a second cancel is refused.
#   Check 48 shows both.
# - Confirmed directly: any other operation answers 403 with a message about a configuration
#   error. This script sends only the five.
# - The message goes in the body as {"userMessage": ...}, and only for ack and nack; it can
#   use Expression Language.
# - Requires `jq`, which builds the body and prints the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers"
TRANSFER_ID="$1"
OPERATION="$2"
MESSAGE="$3"
if [ -z "${TRANSFER_ID}" ] || ! [[ "${OPERATION}" =~ ^(cancel|resubmit|verify|ack|nack)$ ]]; then
    printf "Usage: ./04.logs_transfers_id_operations_POST.sh ID cancel|resubmit|verify|ack|nack [MESSAGE]\n"
    exit 2
fi

BODY_ARGS=()
if [[ "${OPERATION}" =~ ^(ack|nack)$ ]] && [ -n "${MESSAGE}" ]; then
    BODY_ARGS=(-H "Content-Type: application/json" -d "$(jq -cn --arg message "${MESSAGE}" '{userMessage: $message}')")
fi

printf "Performing %s...\n" "${OPERATION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${TRANSFER_ID}/operations?operation=${OPERATION}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" "${BODY_ARGS[@]}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null || printf '%s\n' "${RESPONSE}"
[ "${HTTP_CODE}" = "200" ]
