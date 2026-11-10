#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: the account (01), the copy of the Sentinel settings (02), the settings that report every event to a Sentinel that cannot be reached (03), the fake HTTP server (04),
# then the two scenarios, each with its objects, its flow, its events and its ties to the transfer log (1-upload-push/01 to 04, 2-upload-fusion-partner/01 to 04), and the cleanup, which puts the settings back.
#
# Usage:
# ./00.run_all.sh
#
# Risk: config
#
# Notes:
# - It takes no parameter. It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh, so the settings are put back.
# - It changes the Sentinel settings of the whole server, and the Fusion options, for the time it takes (about three minutes). Read the README first.
# - It needs ST_CALLBACK_HOST (the address of this machine as the server sees it) in set_variables.local.sh, and python3 for the fake HTTP server.
# - The transfers need the End User port: set ST_ENDUSER_PORT in set_variables.local.sh when it is not the admin port minus one.
# - The transfers stay in the transfer log after the cleanup.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
rc=0
for step in "01.accounts_POST" "02.sentinel_GET" "03.sentinel_PATCH" "04.fakeServer_start" \
            "1-upload-push/01.objects_POST" "1-upload-push/02.flow_POST" "1-upload-push/03.events_GET" "1-upload-push/04.logsTransfers_GET" "1-upload-push/99.objects_DELETE" \
            "2-upload-fusion-partner/01.objects_POST" "2-upload-fusion-partner/02.flow_POST" "2-upload-fusion-partner/03.events_GET" "2-upload-fusion-partner/04.logsTransfers_GET" "2-upload-fusion-partner/99.objects_DELETE"; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh" || rc=1
exit "${rc}"
