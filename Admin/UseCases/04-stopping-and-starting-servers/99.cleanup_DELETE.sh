#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Puts back what the steps changed, then removes what they kept: the daemon is started when it was Running at the start (the copy step 01 saved) and is not now, and its servers that were
# active are started when they are not. Then the copy and the administrator's session are removed. It can be run twice: the second time finds nothing to put back.
#
# Usage:
# ./99.cleanup_DELETE.sh [DAEMON]
#
#   DAEMON  the daemon the steps worked on (default ftp)
#
# Risk: write
#
# Notes:
# - Written for this use case. Only the daemon given is put back, and the AS2 daemon never is: the script refuses it at once (exit 2), because the lab's AS2 server is off by design and cannot be started.
# - A daemon that was NOT Running at the start is left as it is. Without a saved copy (step 01 did not run) nothing is started: the script cannot know what the start was.
# - It waits for the daemon, then for its servers, as steps 03 and 05 do, up to 120 seconds each. A daemon or server that does not come back makes the exit code 1, and the copy is kept so that it can be run again.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh [DAEMON]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAEMON.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAEMON="${1:-${DEFAULT_DAEMON}}"
uc_check_daemon "${DAEMON}" "${USAGE}"
if [ "${DAEMON}" = "as2" ]; then printf "The as2 daemon is never started by this use case. Nothing was sent.\n%s\n" "${USAGE}"; exit 2; fi

STATUS=0
st_session
if [ -s "${DAEMONS_STATE}" ] && [ -s "${SERVERS_STATE}" ]; then
    saved=$(jq -r --arg key "${DAEMON}Status" '.[$key] // "unknown"' "${DAEMONS_STATE}")
    now=$(uc_daemon_status "${DAEMON}")
    if [ "${saved}" = "Running" ] && [ "${now}" != "Running" ]; then
        echo "The ${DAEMON} daemon was Running at the start and is: ${now}. Starting it..."
        result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X POST "${ST_URL}/daemons/operations?operation=start&daemon=${DAEMON}" -H "accept: application/json" -H "Referer: ${REFERER}" \
                 -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
        code=${result##*$'\n'}
        body=${result%$'\n'*}
        echo "HTTP ${code}"
        printf '%s' "${body}" | uc_results 2>/dev/null
        if [ "${code}" != "200" ] || ! printf '%s' "${body}" | uc_all_successful; then
            echo "The start was not accepted. A stop may still be in progress: giving the daemon 15 seconds, then trying once more."
            if ! uc_wait_daemon "${DAEMON}" "Running" 15 >/dev/null; then
                curl -k -s -o /dev/null -b "${JAR}" -X POST "${ST_URL}/daemons/operations?operation=start&daemon=${DAEMON}" -H "accept: application/json" -H "Referer: ${REFERER}" \
                     -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
            fi
        fi
        uc_wait_daemon "${DAEMON}" "Running" 120 || STATUS=1
    else
        echo "The ${DAEMON} daemon is as it was at the start (${now}): nothing to put back."
    fi
    if [ "${saved}" = "Running" ] && [ "${STATUS}" = "0" ]; then
        if ! uc_wait_servers "${DAEMON}" 120; then
            uc_start_inactive_servers "${DAEMON}" || STATUS=1
            uc_wait_servers "${DAEMON}" 120 || STATUS=1
        fi
    fi
else
    echo "There is no saved copy of the start: nothing is put back."
fi

if [ "${STATUS}" = "0" ]; then
    rm -f "${DAEMONS_STATE}" "${SERVERS_STATE}"
else
    echo "Something is not as it was: the saved copy is kept, so that this can be run again."
fi
if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
exit ${STATUS}
