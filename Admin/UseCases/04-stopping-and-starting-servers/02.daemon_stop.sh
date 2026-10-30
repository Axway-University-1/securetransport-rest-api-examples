#!/bin/bash
# ==============================================================================
# Script Name: 02.daemon_stop.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 2: stop one daemon. POST /daemons/operations with operation=stop, the daemon, and graceful=true (the default here, said out loud) so that the
# connections in progress finish first. The answer is read: a 200 does not say it worked, isSuccessful does. This script says what each answer means.
#
# Usage:
# ./02.daemon_stop.sh DAEMON stop-the-DAEMON-daemon [GRACEFUL] [TIMEOUT]
#
#   DAEMON      ftp, http, ssh, as2 or pesit
#   stop-the-DAEMON-daemon
#               the confirmation of a stop: this exact word, with the daemon's name in it (stop-the-ftp-daemon). Without it, or with any other word, the script prints
#               this usage, sends NOTHING and exits 2
#   GRACEFUL    true (default) lets the connections in progress finish; false stops at once. Any other value is refused here, before a call (the server does not check it)
#   TIMEOUT     seconds to wait for the connections, a whole number, only with GRACEFUL true (optional; the daemon's own timeout when left out)
#
# Risk: disruptive - the daemon and every protocol server on it stop answering until step 04
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/05.daemons_operations_POST.sh (the same confirmation word and the same answer reading).
# - A stop takes the servers of that protocol down with it. Do it on a server that is yours.
# - The answer is a bare list, [{daemon, message, isSuccessful}]; the reference says an object that holds the list. This script reads both.
# - 200 with isSuccessful true: the stop was accepted. The daemon may not be down yet (step 03 waits for it). 200 with isSuccessful false: nothing was stopped, and the message says why
#   (for example "Daemon FTP is already stopped."). Any other status: the server refused the call.
# - A daemon that is already Not running is not asked to stop: the script says so and sends nothing.
# - A graceful stop with a timeout goes on in the server after this script returns. Do not start the daemon again before step 03 has seen it Not running.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.daemon_stop.sh DAEMON stop-the-DAEMON-daemon [GRACEFUL] [TIMEOUT]"
DAEMON="$1"
if [ "$#" -lt 2 ]; then
    if [ "$#" -eq 1 ]; then uc_check_daemon "${DAEMON}" "${USAGE}"; printf "This stops the %s daemon of the whole server. Nothing was sent. To go on, give the word stop-the-%s-daemon as the second parameter.\n" "${DAEMON}" "${DAEMON}"; fi
    printf "%s\n" "${USAGE}"
    exit 2
fi
uc_check_daemon "${DAEMON}" "${USAGE}"
if [ "$2" != "stop-the-${DAEMON}-daemon" ]; then
    printf "This stops the %s daemon of the whole server: its clients are refused until it is started again.\n" "${DAEMON}"
    printf "Nothing was sent. To go on, give the word stop-the-%s-daemon as the second parameter.\n%s\n" "${DAEMON}" "${USAGE}"
    exit 2
fi
if [ "$#" -gt 4 ]; then printf "%s parameters were given, and at most 4 are taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
GRACEFUL="${3:-true}"
TIMEOUT="$4"
if [ "${GRACEFUL}" != "true" ] && [ "${GRACEFUL}" != "false" ]; then
    printf "GRACEFUL is '%s': it must be true or false. The server does not check it (it takes any text), so this script does. Nothing was sent.\n%s\n" "${GRACEFUL}" "${USAGE}"
    exit 2
fi
if [ -n "${TIMEOUT}" ]; then
    uc_check_seconds TIMEOUT "${TIMEOUT}" "${USAGE}"
    if [ "${GRACEFUL}" != "true" ]; then printf "TIMEOUT only goes with GRACEFUL true. Nothing was sent.\n%s\n" "${USAGE}"; exit 2; fi
fi
st_session

status=$(uc_daemon_status "${DAEMON}")
echo "The ${DAEMON} daemon is now: ${status}"
if [ "${status}" = "Not running" ]; then
    echo "It is already stopped: nothing was sent."
    exit 0
fi

QUERY="operation=stop&daemon=${DAEMON}&graceful=${GRACEFUL}"
if [ -n "${TIMEOUT}" ]; then QUERY="${QUERY}&timeout=${TIMEOUT}"; fi
echo "Stopping the ${DAEMON} daemon (graceful=${GRACEFUL}${TIMEOUT:+, timeout=${TIMEOUT}})..."
result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X POST "${ST_URL}/daemons/operations?${QUERY}" -H "accept: application/json" -H "Referer: ${REFERER}" \
         -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
code=${result##*$'\n'}
body=${result%$'\n'*}
echo "HTTP ${code}"
if [ "${code}" != "200" ]; then
    printf '%s' "${body}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${body}"
    echo "The server refused the call. Nothing was stopped."
    exit 1
fi
printf '%s' "${body}" | uc_results
if ! printf '%s' "${body}" | uc_all_successful; then
    echo "The server answered 200, but isSuccessful is not true: the daemon was NOT stopped. Read the message above."
    exit 1
fi
echo "Accepted. That is not the same as stopped: the daemon goes down a moment later. Step 03 waits for it."
