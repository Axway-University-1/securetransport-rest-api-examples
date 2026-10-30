#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: look (01), stop (02), wait for it (03), start (04), wait for the daemon (03) and for its servers (05), compare (06), then the cleanup.
#
# Usage:
# ./00.run_all.sh [DAEMON]
#
#   DAEMON  the daemon to stop and start (default ftp)
#
# Risk: disruptive - the daemon and its servers are down for about half a minute
#
# Notes:
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh, which starts the daemon again when it was left stopped.
# - Run it on the ftp daemon of a test server. Never on http (the End User API runs on it, and so may the session that runs this), and not on a daemon whose users you cannot warn.
# - The AS2 daemon is refused: a server with AS2 off cannot start it again.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [DAEMON]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAEMON.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAEMON="${1:-ftp}"
case "${DAEMON}" in
    ftp|http|ssh|pesit) ;;
    *) printf "DAEMON is '%s': it must be ftp, http, ssh or pesit (the AS2 daemon is not stopped by this use case). Nothing was sent.\n%s\n" "${DAEMON}" "${USAGE}"; exit 2 ;;
esac
rc=0
run_step() {
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}" || { rc=1; echo "$1 failed."; return 1; }
}
run_step 01.daemons_GET &&
run_step 02.daemon_stop "${DAEMON}" "stop-the-${DAEMON}-daemon" true &&
run_step 03.daemon_wait "${DAEMON}" "Not running" 90 &&
run_step 04.daemon_start "${DAEMON}" &&
run_step 03.daemon_wait "${DAEMON}" "Running" 90 &&
run_step 05.servers_wait "${DAEMON}" 60 &&
run_step 06.compare_with_start
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh" "${DAEMON}" || rc=1
exit ${rc}
