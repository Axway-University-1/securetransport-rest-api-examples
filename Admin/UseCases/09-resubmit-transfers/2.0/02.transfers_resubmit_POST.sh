#!/bin/bash
# ==============================================================================
# Script Name: 02.transfers_resubmit_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 2.0, step 2: resubmit the transfers of an account, one by one. The API 2.0 resubmits one transfer for each call, `POST /logs/transfers/{id}/operations?operation=resubmit`, so the script
# reads the list of the transfers that were not resubmitted yet (`resubmitted=false`) and makes the call for each of them. You see what it does to each, and one that is refused does not stop
# the others.
#
# Usage:
# ./02.transfers_resubmit_POST.sh [ACCOUNT]
#
#   ACCOUNT  the account whose transfers to resubmit (default: example_rsb_a)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/16.TransferLogs/04.logs_transfers_id_operations_POST.sh (the call for one transfer).
# - What is resubmitted is only what the list shows: the account, after the time of step 02, not resubmitted yet. The same filter is the one thing that keeps this loop from touching more.
# - Confirmed directly: a resubmit answers 200 "Transfer with id ... was successfully resubmitted." The original is then flagged resubmitted: true, and the resubmit is a NEW transfer in the log
#   (so three transfers resubmitted make six in the log), with resubmitted: false. A second run of this script would therefore resubmit the copies. A transfer that failed is not resubmittable: 400.
# - The script exits 1 when a call is refused, after it has tried all the transfers, or when there is nothing to resubmit.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./02.transfers_resubmit_POST.sh [ACCOUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="${1:-${A20}}"
uc_check_account "${ACCOUNT}" "${USAGE}"
st_session

QUERY=("account=${ACCOUNT}" "resubmitted=false" "fields=id,filename" "sortByStartTime=ascending" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
uc_get logs/transfers "${QUERY[@]}"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /logs/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
COUNT=$(printf '%s' "${LIST_BODY}" | jq -r '.result | length')
if [ "${COUNT}" = "0" ]; then echo "${ACCOUNT} has no transfer that was not resubmitted yet: nothing to do."; exit 1; fi
echo "Resubmitting ${COUNT} transfers of ${ACCOUNT}, one call each..."

OK=0; REFUSED=0
while IFS=$'\t' read -r ID NAME; do
    RESULT=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X POST "${ST_URL}/logs/transfers/${ID}/operations?operation=resubmit" -H "accept: application/json" -H "Referer: ${REFERER}" \
             -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
    CODE="${RESULT##*$'\n'}"
    MESSAGE=$(printf '%s' "${RESULT%$'\n'*}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null)
    if [ "${CODE}" = "200" ]; then OK=$((OK + 1)); else REFUSED=$((REFUSED + 1)); fi
    printf "  %s: HTTP %s, %s\n" "${NAME}" "${CODE}" "${MESSAGE}"
done < <(printf '%s' "${LIST_BODY}" | jq -r '.result[] | [.id.urlrepresentation, .filename] | @tsv')
printf "%s resubmitted, %s refused.\n" "${OK}" "${REFUSED}"
[ "${REFUSED}" -eq 0 ]
