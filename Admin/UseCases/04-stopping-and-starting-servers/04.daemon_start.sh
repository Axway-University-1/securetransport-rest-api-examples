#!/bin/bash
# ==============================================================================
# Script Name: 04.daemon_start.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 4: start the daemon again. POST /daemons/operations with operation=start and the daemon. As with the stop, the answer is read for isSuccessful,
# and it comes BEFORE the daemon is up: step 03 (with STATE Running) waits for it, and step 05 waits for its servers.
#
# Usage:
# ./04.daemon_start.sh DAEMON
#
#   DAEMON  ftp, http, ssh, as2 or pesit
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/05.daemons_operations_POST.sh (a start needs no confirmation word).
# - 200 with isSuccessful true: accepted; the daemon is not Running yet. 200 with isSuccessful false: it did not start, and the message says why ("Daemon FTP is already started.",
#   or for as2 "Can not start AS2 daemon - the default server As2 Default is not enabled."). Any other status: the server refused the call.
# - A daemon that is already Running is not asked to start: the script says so and sends nothing.
# - Starting a daemon starts the servers of its protocol by themselves a few seconds after it is Running (step 05 waits for them).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.daemon_start.sh DAEMON"
if [ "$#" -lt 1 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAEMON.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAEMON="$1"
uc_check_daemon "${DAEMON}" "${USAGE}"
st_session

status=$(uc_daemon_status "${DAEMON}")
echo "The ${DAEMON} daemon is now: ${status}"
if [ "${status}" = "Running" ]; then
    echo "It is already running: nothing was sent."
    exit 0
fi

echo "Starting the ${DAEMON} daemon..."
result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X POST "${ST_URL}/daemons/operations?operation=start&daemon=${DAEMON}" -H "accept: application/json" -H "Referer: ${REFERER}" \
         -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
code=${result##*$'\n'}
body=${result%$'\n'*}
echo "HTTP ${code}"
if [ "${code}" != "200" ]; then
    printf '%s' "${body}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${body}"
    echo "The server refused the call. Nothing was started."
    exit 1
fi
printf '%s' "${body}" | uc_results
if ! printf '%s' "${body}" | uc_all_successful; then
    echo "The server answered 200, but isSuccessful is not true: the daemon was NOT started. Read the message above."
    exit 1
fi
echo "Accepted. That is not the same as running: the daemon comes up a few seconds later (about 11 to 12 on the lab). Step 03 waits for it."
