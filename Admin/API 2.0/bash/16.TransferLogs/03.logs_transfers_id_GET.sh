#!/bin/bash
# ==============================================================================
# Script Name: 03.logs_transfers_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one transfer from the transfer log using the `/logs/transfers/{id}`
# endpoint: its status, the file, who transferred it, over which protocol, and how long it took.
#
# Usage:
# ./03.logs_transfers_id_GET.sh [ID]
#
#   ID  the transfer's id, as 01.logs_transfers_GET.sh lists it under id.urlrepresentation
#       (default: the newest transfer in the log)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The id is the urlrepresentation of the transfer's id object: Base64 of "Id
#   [mTransferStatusId=..., mTransferStartTime=...]". An id in any other form answers 400
#   "Invalid format for transfer ID".
# - Confirmed directly: the fields of one transfer are not those of the list. The list has
#   incoming, protocol and serverInitiated; one transfer has transferType, transferSite,
#   userClass and duration, and fields=incoming answers 400 "Field incoming does not exist".
# - isCancelable and isResubmittable tell whether the server will allow 04.logs_transfers_id_operations_POST.sh
#   to cancel or resubmit this transfer now. Confirmed directly: a transfer in progress is never
#   cancelable, over FTP, HTTP or SSH, whatever its size; a PeSIT pull that failed and is waiting
#   to be retried is; a finished incoming transfer is resubmittable, a failed one is not.
# - Requires `jq`, which looks the newest transfer up and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers"
TRANSFER_ID="$1"
if [ -z "${TRANSFER_ID}" ]; then
    TRANSFER_ID=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" --data-urlencode "sortByStartTime=descending" --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id.urlrepresentation // empty')
    if [ -z "${TRANSFER_ID}" ]; then
        printf "There are no transfers in the log.\n"
        exit 1
    fi
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${TRANSFER_ID}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the transfer (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.status): \(.file) (\(.transferType)), \(.duration)",
  "  account \(.account // "-"), login \(.login // "-"), server \(.serverName // "-"), site \(.transferSite // "-")",
  "  started \(.startTime)",
  "  cancelable: \(if .isCancelable then "yes" else "no" end), resubmittable: \(if .isResubmittable then "yes" else "no" end)"'
