#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: part 1 (01 to 05, the whole server), part 2 (06 to 11, the business units), then the cleanup.
#
# Usage:
# ./00.run_all.sh [DAYS]
#
#   DAYS  how many days 04 and 05 count, today included (default 3)
#
# Risk: write
#
# Notes:
# - The inputs are checked first: a wrong DAYS stops it at once, with the usage, before any call.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# - Part 2 makes three business units and six accounts (06), and 100 transfers with the End User API (07, about a minute): set ST_ENDUSER_PORT in set_variables.local.sh when the End User port is not the admin port minus one.
# - The 100 transfers stay in the transfer log after the cleanup.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [DAYS]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAYS.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAYS="${1:-3}"
if [[ ! "${DAYS}" =~ ^[1-9][0-9]*$ ]]; then
    printf "DAYS is '%s': it must be a whole number of 1 or more.\n%s\n" "${DAYS}" "${USAGE}"
    exit 2
fi
rc=0
for step in "01.settings_GET" "02.activeUsers_GET" "03.generateReport_GET" "04.transfers_billable_count_GET ${DAYS}" "05.report_vs_log ${DAYS}" \
            "06.business_units_POST" "07.transfers_make_POST" "08.global_total_GET" "09.business_unit_accounts_GET example_use_bu1" \
            "10.usage_per_business_unit_GET example_use_bu1" "10.usage_per_business_unit_GET example_use_bu2" "10.usage_per_business_unit_GET example_use_bu3" "11.usage_all_business_units_GET"; do
    set -- ${step}
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}" || { rc=1; echo "$1 failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
