#!/bin/bash
# ==============================================================================
# Script Name: 07.transfers_make_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 2: the users work. As the End User API (Basic authentication), each of the six accounts uploads its number of files (25 and 15, 20 and 15, 15 and 10): 100 inbound transfers,
# 40 for example_use_bu1, 35 for example_use_bu2 and 25 for example_use_bu3. Before it starts, it keeps the time (state.local.window) and what the usage report says for today (state.local.report), so that 08 can
# ask the report how much the server counted since. Then it waits until the log shows the 100.
#
# Usage:
# ./07.transfers_make_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/UseCases/03-files-and-folders/02.files_POST_upload.sh, with Basic authentication (the password of 06 in state.local.password), once for each file.
# - The End User API is on its own port: ST_ENDUSER_PORT when the settings set it (add `export ST_ENDUSER_PORT=8443` to set_variables.local.sh), otherwise the admin port minus one.
# - Every inbound transfer is billable, so the 100 uploads are 100 billable transfers. (A download after an upload is the first outbound of its chain, and is not billable: this step makes none, to keep the total round.)
# - The numbers are small on purpose: 100 uploads of one line take about a minute. The transfers stay in the transfer log after the cleanup: no API call deletes a log entry.
# - It waits up to 60 seconds for the log to show the transfers (the log is written a moment after the transfer), and says so when it does not.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./07.transfers_make_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ ! -s "${PASSWORD_FILE}" ]; then
    echo "There is no $(basename "${PASSWORD_FILE}"): run 06.business_units_POST.sh first (it makes the accounts and the password)."
    exit 2
fi
PASSWORD=$(cat "${PASSWORD_FILE}")
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'Usage report test file.\n' > "${LOCAL}"

TODAY=$(uc_ddmmyyyy_ago 0)
uc_get statisticsSummary/generateReport "startDate=${TODAY}" "endDate=${TODAY}"
if [ "${LIST_CODE}" != "200" ]; then printf "The report for %s: HTTP %s: %s\n" "${TODAY}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
BEFORE=$(printf '%s' "${LIST_BODY}" | jq -r '.meta.reportSummary["ST.Transfers"] // empty')
if [[ ! "${BEFORE}" =~ ^[0-9]+$ ]]; then echo "The report for ${TODAY} has no ST.Transfers."; exit 1; fi
printf '%s %s\n' "${TODAY}" "${BEFORE}" > "${REPORT_FILE}"
echo "The usage report for ${TODAY} says ST.Transfers ${BEFORE} before the users work (state.local.report)."
uc_rfc_seconds_ago 2 > "${WINDOW_FILE}"
echo "The transfers of this run are the ones after $(cat "${WINDOW_FILE}") (state.local.window)."

echo "The six accounts log in on ${ST_SERVER}:${ST_ENDUSER_PORT} with the password of 06 and upload ${UC_TOTAL} files in all."
for LINE in "${UC_ACCOUNTS[@]}"; do
    read -r NAME BU _ _ UPLOADS <<< "${LINE}"
    FAILED=0
    for N in $(seq 1 "${UPLOADS}"); do
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${NAME}:${PASSWORD}" -X POST "${EU_URL}/files" -F "file=@${LOCAL};filename=use_${N}.txt" -H "accept: application/json" -H "Referer: ${REFERER}")
        if [ "${code}" = "000" ]; then echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1; fi
        [[ "${code}" == 20* ]] || { echo "  ${NAME} uploads use_${N}.txt: HTTP ${code}"; exit 1; }
    done
    echo "  ${NAME} (${BU}) uploaded ${UPLOADS} files."
done

FROM=$(cat "${WINDOW_FILE}")
for ATTEMPT in $(seq 1 60); do
    SEEN=""
    for BU in "${UC_BUS[@]}"; do
        uc_count "the log of ${BU}" logs/transfers "businessUnit=${BU}" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
        SEEN="${SEEN} ${BU}=${COUNT}"
        [ "${COUNT}" -ge "$(uc_bu_uploads "${BU}")" ] || MISSING=1
    done
    if [ -z "${MISSING:-}" ]; then
        echo "The log shows:${SEEN}."
        exit 0
    fi
    MISSING=""
    sleep 1
done
echo "After 60 seconds the log shows:${SEEN}. Expected 40, 35 and 25."
exit 1
