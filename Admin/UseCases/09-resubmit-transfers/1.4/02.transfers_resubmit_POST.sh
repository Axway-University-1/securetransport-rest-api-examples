#!/bin/bash
# ==============================================================================
# Script Name: 02.transfers_resubmit_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 1.4, step 2: resubmit the transfers of an account with ONE call, `POST /api/v1.4/transfers/resubmit`. The API 2.0 has no such call. The criteria are the ones of step 01, so the call touches
# the transfers that 01 listed. The server answers a list, one entry for each transfer: OK or ERROR, with a message.
#
# Usage:
# ./02.transfers_resubmit_POST.sh ACCOUNT
#
#   ACCOUNT  the account whose transfers to resubmit (required: there is no default, on purpose)
#
# Risk: write
#
# Notes:
# - Written for this use case. ACCOUNT is required, and the call is never made without a criterion: a call of this kind with nothing but limit would resubmit every transfer in the log of the server,
#   whoever made it (this was not tried, on purpose).
# - Confirmed directly: the call answers 200 whatever the entries say. A transfer that could not be resubmitted is an entry {"status": "ERROR", "message": "Error while resubmitting transfer with id ..."},
#   in a 200. So the script reads the entries, not the status, and exits 1 when one is not OK.
# - Confirmed directly: a resubmit of the transfers of an account that was already deleted answered ERROR for each, and still flagged the originals resubmitted: true. The answer gives no cause.
# - Confirmed directly: resubmitted=false does not stop a second run from resubmitting. The new transfers that the first run made are transfers too, with resubmitted false: run it again and it resubmits
#   them. One run for each batch.
# - With no transfer that fits the criteria the server answers 400 "No transfers found for resubmit.", and the script exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./02.transfers_resubmit_POST.sh ACCOUNT"
if [ "$#" -ne 1 ]; then printf "%s parameters were given, and 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="$1"
uc_check_account "${ACCOUNT}" "${USAGE}"

QUERY=("accountOrLogin=${ACCOUNT}" "resubmitted=false" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
echo "Resubmitting with one call: ${QUERY[*]}"
uc14_call POST transfers/resubmit "${QUERY[@]}"
if [ "${LIST_CODE}" != "200" ]; then
    printf "POST /api/v1.4/transfers/resubmit: HTTP %s: %s\n" "${LIST_CODE}" "$(printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null)"
    exit 1
fi
if ! printf '%s' "${LIST_BODY}" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    echo "HTTP 200, but the answer is not a list of entries: $(printf '%s' "${LIST_BODY}" | head -c 200)"
    exit 1
fi
printf '%s' "${LIST_BODY}" | jq -r '.[] | "  \(.status): \(.message)"'
OK=$(printf '%s' "${LIST_BODY}" | jq -r '[.[] | select(.status == "OK")] | length')
TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r 'length')
printf "HTTP 200: %s entries, %s OK, %s not OK.\n" "${TOTAL}" "${OK}" "$((TOTAL - OK))"
[ "${OK}" -eq "${TOTAL}" ]
