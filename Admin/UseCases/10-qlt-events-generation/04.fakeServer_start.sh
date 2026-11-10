#!/bin/bash
# ==============================================================================
# Script Name: 04.fakeServer_start.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Step 4: start the fake HTTP server, on THIS machine, in the background. It stands in for the two servers the scenarios talk to: "another server", which a Generic HTTP site pushes a file to, and Fusion. It
# accepts what SecureTransport sends and answers what SecureTransport accepts, and it logs each request it is sent, so that the scenarios can show what the server sent. It is not a loop back to
# SecureTransport: nothing it receives makes an event of its own.
#
# Usage:
# ./04.fakeServer_start.sh
#
# Risk: none
#
# Notes:
# - Written for this use case. The server is fake_http_server.py (Python 3, standard library only; its header says what it answers).
# - It listens on every address of this machine, on ST_CALLBACK_PORT (default 18081), and the SecureTransport server must reach it at ST_CALLBACK_HOST: set that in set_variables.local.sh to the address of this
#   machine as the server sees it. Nothing here checks that the server reaches it; the flow of a scenario says so when the server sends nothing.
# - The process id is kept in state.local.fake_server.pid and the requests in state.local.fake_server.log. 99.cleanup_DELETE.sh stops it, by that process id, after checking that the process is a
#   fake_http_server.py: no other process is ever stopped. A server that runs already is left as it is (exit 0).
# - Exit codes: 0 when the server runs, 1 when it cannot be started, 2 when a parameter is given.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.fakeServer_start.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
[ -n "${FAKE_SERVER_HOST}" ] || { echo "ST_CALLBACK_HOST is not set: it is the address of THIS machine as the SecureTransport server reaches it. Add it to set_variables.local.sh."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is needed to run the fake HTTP server."; exit 1; }
if uc_fake_alive; then echo "The fake HTTP server runs already (process $(uc_fake_pid)). It is left as it is."; exit 0; fi

: > "${FAKE_LOG_FILE}"
nohup python3 "${UC_DIR}/fake_http_server.py" "${FAKE_SERVER_PORT}" "${FAKE_LOG_FILE}" > /dev/null 2>&1 &
printf '%s\n' "$!" > "${FAKE_PID_FILE}"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if curl -s -o /dev/null -m 2 -H "Referer: ${REFERER}" "http://127.0.0.1:${FAKE_SERVER_PORT}/"; then
        echo "The fake HTTP server runs (process $(cat "${FAKE_PID_FILE}")), on port ${FAKE_SERVER_PORT}. The SecureTransport server will reach it at http://${FAKE_SERVER_HOST}:${FAKE_SERVER_PORT}."
        exit 0
    fi
done
echo "The fake HTTP server did not start (is port ${FAKE_SERVER_PORT} in use? set ST_CALLBACK_PORT)."
uc_fake_stop
exit 1
