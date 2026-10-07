#!/bin/bash
# ==============================================================================
# Script Name: 05.logs_transfers_pullSummary_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the status summary of a pull using the
# `/logs/transfers/pullSummary/{operationIndex}` endpoint: how many of the files it found were
# pulled, failed, are being retried, are in progress or on hold.
#
# Usage:
# ./05.logs_transfers_pullSummary_GET.sh OPERATION_INDEX
#
#   OPERATION_INDEX  the pull's index, from the link in the 202 answer of
#                    15.Transfers/01.transfers_operations_POST_pull.sh (operationIndex=...)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The summary counts the files the pull found, not the pull itself: a pull that found nothing,
#   or could not connect, shows all zeros.
# - Confirmed directly: an index nobody used is not an error: it answers 200 with every count
#   0. Two pulls with one index add up.
# - Confirmed directly: of the transfers a pull leaves in the log, only the one the pull itself
#   started carries the operationIndex; the others show (none).
# - "to retry" are pulls that failed and will be tried again: those are the ones
#   04.logs_transfers_id_operations_POST.sh can cancel, after which they count as failed.
# - Requires `jq`, which prints the counts.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers"
OPERATION_INDEX="$1"
if [ -z "${OPERATION_INDEX}" ]; then
    printf "Usage: ./05.logs_transfers_pullSummary_GET.sh OPERATION_INDEX\n"
    exit 2
fi
ENCODED=$(jq -rn --arg index "${OPERATION_INDEX}" '$index | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/pullSummary/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the summary (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  \(.totalCount) file(s): \(.successful) pulled, \(.failed) failed, \(.inRetry) to retry, \(.inProgress) in progress, \(.onHold) on hold"'
