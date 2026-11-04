#!/bin/bash
# ==============================================================================
# Script Name: 02.uploads_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# Step 2: the two accounts upload three small files each, report_1.txt to report_3.txt, with the End User API. Every upload is one transfer in the transfer log. The script waits until the
# log shows all six as Processed, and keeps the time it started in state.local.window: the transfers of this run are the ones after it, so a transfer of an earlier run of the same accounts is never touched.
#
# Usage:
# ./02.uploads_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/UseCases/03-files-and-folders/02.files_POST_upload.sh, with Basic authentication (the password of 01 in state.local.password), once for each file.
# - The End User API is on its own port: ST_ENDUSER_PORT when the settings set it (add `export ST_ENDUSER_PORT=8443` to set_variables.local.sh), otherwise the admin port minus one.
# - Confirmed directly: an upload with one POST /files is a transfer with the status Processed. (An upload made with POST /fileOperations and a PUT is logged as Failed, "Transfer aborted by
#   user", unless it is completed: not used here.)
# - The log shows a transfer within a second or two, but it is In Progress for a moment more, and a transfer that is In Progress cannot be resubmitted (the 2.0 call answers 400, the 1.4 call an ERROR entry).
#   So the script waits for the status Processed, up to 60 seconds.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.uploads_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
[ -s "${PASSWORD_FILE}" ] || { echo "There is no password for the accounts: run 01.accounts_POST.sh first."; exit 1; }
st_session

PASSWORD=$(cat "${PASSWORD_FILE}")
LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'a small file that is resubmitted\n' > "${LOCAL}"
uc_rfc_seconds_ago 2 > "${WINDOW_FILE}"
echo "The transfers of this run are the ones after $(cat "${WINDOW_FILE}") (state.local.window)."

for LINE in "${UC_ACCOUNTS[@]}"; do
    NAME="${LINE%% *}"
    for N in $(seq 1 "${UPLOADS}"); do
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${NAME}:${PASSWORD}" -X POST "${EU_URL}/files" -F "file=@${LOCAL};filename=report_${N}.txt" -H "accept: application/json" -H "Referer: ${REFERER}")
        if [ "${code}" = "000" ]; then echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1; fi
        [[ "${code}" == 20* ]] || { echo "${NAME} uploads report_${N}.txt: HTTP ${code}"; exit 1; }
    done
    echo "  ${NAME} uploaded ${UPLOADS} files."
done

FROM=$(uc_window)
for ATTEMPT in $(seq 1 60); do
    SEEN=""; MISSING=""
    for LINE in "${UC_ACCOUNTS[@]}"; do
        NAME="${LINE%% *}"
        uc_get logs/transfers "account=${NAME}" "startTimeAfter=${FROM}" "limit=100" "fields=status"
        if [ "${LIST_CODE}" != "200" ]; then printf "The transfer log of %s: HTTP %s: %s\n" "${NAME}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
        COUNT=$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select(.status == "Processed")] | length')
        SEEN="${SEEN} ${NAME}=${COUNT}"
        [ "${COUNT}" -ge "${UPLOADS}" ] || MISSING=1
    done
    if [ -z "${MISSING}" ]; then echo "The log shows, as Processed:${SEEN}."; exit 0; fi
    sleep 1
done
echo "After 60 seconds the log shows, as Processed:${SEEN}. Expected ${UPLOADS} for each."
exit 1
