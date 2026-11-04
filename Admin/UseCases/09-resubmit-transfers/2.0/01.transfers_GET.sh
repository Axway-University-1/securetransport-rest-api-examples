#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 2.0, step 1: look at the transfers of an account in the transfer log: the file, the status, and whether the transfer was resubmitted already. This is what you read before you resubmit
# anything. The log of the API 2.0 is `GET /logs/transfers`; the account is filtered with `account=`, and the transfers of this run with `startTimeAfter=`.
#
# Usage:
# ./01.transfers_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account whose transfers to list (default: example_rsb_a)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/16.TransferLogs/01.logs_transfers_GET.sh and 03.logs_transfers_id_GET.sh (what the id looks like).
# - The id of a transfer is an object: {mTransferStatusId, mTransferStartTime, urlrepresentation}. The one that goes into the URL of a call is `urlrepresentation`, the Base64 of "Id
#   [mTransferStatusId=..., mTransferStartTime=...]". The script decodes the first one so that you can see it.
# - It reads the transfers after the time kept by 02 (state.local.window). Without it, the whole log of the account.
# - `fields=` narrows the answer to what is read here. `resubmitted` is true on a transfer that was resubmitted: the original is flagged, and the resubmit is a new transfer.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./01.transfers_GET.sh [ACCOUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="${1:-${A20}}"
uc_check_account "${ACCOUNT}" "${USAGE}"
st_session

QUERY=("account=${ACCOUNT}" "fields=id,filename,status,resubmitted" "sortByStartTime=ascending" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
uc_get logs/transfers "${QUERY[@]}"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /logs/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount // 0')
printf "%s transfers of %s%s:\n" "${TOTAL}" "${ACCOUNT}" "${FROM:+ after ${FROM}}"
printf '%s' "${LIST_BODY}" | jq -r '.result[] | "  \(.filename)  \(.status)  resubmitted: \(.resubmitted)"'
FIRST=$(printf '%s' "${LIST_BODY}" | jq -r '.result[0].id.urlrepresentation // empty')
if [ -n "${FIRST}" ]; then
    printf "The id of the first one, as it goes into a URL: %s\n" "${FIRST}"
    printf "...which is the Base64 of: %s\n" "$(printf '%s' "${FIRST}" | base64 -d 2>/dev/null || printf '%s' "${FIRST}" | base64 -D)"
fi
[ "${TOTAL}" -gt 0 ] || { echo "There are no transfers: run 02.uploads_POST.sh first."; exit 1; }
