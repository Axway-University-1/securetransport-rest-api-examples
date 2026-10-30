#!/bin/bash
# ==============================================================================
# Script Name: 03.daemon_wait.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 3 (and again after step 4): wait for a daemon to say what you expect. The answer to a stop or a start comes before the daemon has changed, so this
# polls GET /daemons every 3 seconds until the status of the daemon is the one asked for, and says how long it took.
#
# Usage:
# ./03.daemon_wait.sh DAEMON STATE [SECONDS]
#
#   DAEMON   ftp, http, ssh, as2 or pesit
#   STATE    Running or "Not running" (quote it: it has a space)
#   SECONDS  how long to wait at most, a whole number (default 60)
#
# Risk: read
#
# Notes:
# - Written for this use case, a wait loop: the same GET /daemons as 01.daemons_GET.sh, repeated.
# - On the lab, a daemon says Running about 11 to 12 seconds after the answer to its start. A graceful stop with connections in progress takes as long as those connections need.
# - The time it says is the larger of the clock and 3 seconds for each try.
# - Exit 1 when the daemon is not in that state in time: say so, and look at it with 01 before doing anything else.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.daemon_wait.sh DAEMON STATE [SECONDS]"
if [ "$#" -lt 2 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
if [ "$#" -gt 3 ]; then printf "%s parameters were given, and at most 3 are taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAEMON="$1"
STATE="$2"
SECONDS_LIMIT="${3:-60}"
uc_check_daemon "${DAEMON}" "${USAGE}"
case "${STATE}" in
    "Running"|"Not running") ;;
    *) printf "STATE is '%s': it must be Running or \"Not running\", as GET /daemons says it. Nothing was sent.\n%s\n" "${STATE}" "${USAGE}"; exit 2 ;;
esac
uc_check_seconds SECONDS "${SECONDS_LIMIT}" "${USAGE}"
st_session

echo "Waiting for the ${DAEMON} daemon to be '${STATE}' (at most ${SECONDS_LIMIT} seconds)..."
uc_wait_daemon "${DAEMON}" "${STATE}" "${SECONDS_LIMIT}"
