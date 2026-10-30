#!/bin/bash
# ==============================================================================
# Script Name: 05.servers_wait.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 5: wait for the servers of that protocol to be active. A daemon that says Running is only the listener process: the servers on it come up by themselves
# a few seconds later. This polls GET /servers until every server of the protocol that was active at the start (step 01 saved them) is active again. A server that is still not
# active when the time is up is started with POST /servers/operations, the answer is read for isSuccessful, and the wait runs once more.
#
# Usage:
# ./05.servers_wait.sh DAEMON [SECONDS]
#
#   DAEMON   ftp, http, ssh, as2 or pesit
#   SECONDS  how long to wait at most, each time, a whole number (default 60)
#
# Risk: write (only when a server has to be started)
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/06.servers_GET.sh and 13.servers_operations_POST.sh. The wait is written for this use case.
# - Without a copy from step 01 it waits for every server of that protocol, including one that an administrator had stopped on purpose: it then ends with exit 1.
# - On the lab the servers of a daemon are active about 3 to 8 seconds after the daemon says Running, and about 15 to 19 seconds after the answer to its start.
# - 200 with isSuccessful false on a server start is a failure, whatever the status code says. The script says so and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.servers_wait.sh DAEMON [SECONDS]"
if [ "$#" -lt 1 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAEMON="$1"
SECONDS_LIMIT="${2:-60}"
uc_check_daemon "${DAEMON}" "${USAGE}"
uc_check_seconds SECONDS "${SECONDS_LIMIT}" "${USAGE}"
st_session

echo "Waiting for the ${DAEMON} servers to be active (at most ${SECONDS_LIMIT} seconds)..."
if uc_wait_servers "${DAEMON}" "${SECONDS_LIMIT}"; then exit 0; fi

echo "They did not come up by themselves. Starting what is not active:"
uc_start_inactive_servers "${DAEMON}" || { echo "A server could not be started."; exit 1; }
uc_wait_servers "${DAEMON}" "${SECONDS_LIMIT}"
