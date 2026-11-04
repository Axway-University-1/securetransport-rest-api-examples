#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: the setup (01 and 02), the API 2.0 way (2.0/01 to 03, on the account example_rsb_a), the API 1.4 way (1.4/01 to 03, on example_rsb_b), then the cleanup.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
#
# Notes:
# - It takes no parameter. It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# - The uploads need the End User port: set ST_ENDUSER_PORT in set_variables.local.sh when it is not the admin port minus one.
# - The six transfers and their resubmits stay in the transfer log after the cleanup (about 10 seconds in all).
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
rc=0
for step in "01.accounts_POST" "02.uploads_POST" "2.0/01.transfers_GET" "2.0/02.transfers_resubmit_POST" "2.0/03.check_GET" \
            "1.4/01.transfers_GET" "1.4/02.transfers_resubmit_POST example_rsb_b" "1.4/03.check_GET"; do
    set -- ${step}
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}" || { rc=1; echo "$1 failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh" || rc=1
exit "${rc}"
