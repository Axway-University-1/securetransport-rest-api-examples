#!/bin/bash
# ==============================================================================
# Script Name: run_business_units.sh
# Author: Plamen Milenkov
# Created: 2026-11-18
# Location: Sofia
# ==============================================================================
# Description:
# Runs the transfers of this feature for the users of two business units, so that
# the two units end with a different number of transfers:
#
#   1. Creates the two business units (BT_BU_1 and BT_BU_2), each with its base
#      folder <BT_HOME_ROOT>/<unit>, using the `/businessUnits` endpoint.
#   2. Runs the whole feature (00.run_all.sh) once for each user: BT_BU_1_USERS
#      users in the first unit (3 by default) and BT_BU_2_USERS in the second (1
#      by default). A user is a test account, created in its unit, with its home
#      folder inside the unit's base folder. Each user does the same transfers as
#      one run of 00.run_all.sh, so the first unit does three times the transfers
#      of the second.
#   3. Counts, for each unit, the transfers of its users since the run started:
#      all of them, and the billable ones, next to what the rule predicts.
#
# Usage:
# ./run_business_units.sh [--cleanup | --remove]
#
#   (no option)  create, run and report, and leave everything in place
#   --cleanup    after the report, remove everything again
#   --remove     only remove what an earlier run left (the users with their objects, then
#                the two business units), without running anything
#
# Risk: write
#
# Notes:
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh. The names, the
#   number of users per unit and the number of files per user are in settings.sh.
# - The users are named after their unit: btBusinessUnit1User1, btBusinessUnit1User2, and so on.
# - The two partner accounts are shared by all the users, and stay in the default unit:
#   the transfers counted for a unit are those of its users' own accounts.
# - The transfer log has no business unit filter, so a unit's count is the sum of the
#   counts of its users (the `account` filter of `/logs/transfers`, since the start of
#   this run). Run it again with the same names the same day and the counts include the
#   earlier run: --remove first.
# - Stops at the first user whose run fails, and leaves everything in place to look at.
# - A unit is deleted only after its users, and the server refuses to delete a unit that
#   still has accounts: --remove says so and exits 1.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
usage() {
    printf "Usage: ./run_business_units.sh [--cleanup | --remove]\n"
    exit 2
}
MODE="run"
[ "$#" -gt 1 ] && usage
case "$1" in
    "")        ;;
    --cleanup) MODE="cleanup" ;;
    --remove)  MODE="remove" ;;
    *)         usage ;;
esac

source "${SCRIPT_DIR}/settings.sh"

for n in "${BT_BU_1_USERS}" "${BT_BU_2_USERS}"; do
    [[ "${n}" =~ ^[1-9][0-9]*$ ]] || { printf "The number of users per unit must be a whole number, 1 or more: %s\n" "${n}"; exit 2; }
done
if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# The users of a unit: <unit>User1 to <unit>User<count>
BU_NAMES=("${BT_BU_1}" "${BT_BU_2}")
BU_COUNTS=("${BT_BU_1_USERS}" "${BT_BU_2_USERS}")
unit_users() {
    local unit="$1" count="$2" i
    for i in $(seq 1 "${count}"); do printf "%s\n" "${unit}User${i}"; done
}

# remove_all: each user with everything it owns, then the two business units
remove_all() {
    local i unit user failed=0
    for i in 0 1; do
        for user in $(unit_users "${BU_NAMES[i]}" "${BU_COUNTS[i]}"); do
            printf "\n--- removing %s ---\n" "${user}"
            BT_RUN_BUSINESS_UNIT="${BU_NAMES[i]}" bash "${SCRIPT_DIR}/99.cleanup_DELETE.sh" "${user}" || failed=1
        done
    done
    for unit in "${BU_NAMES[@]}"; do
        if ar_admin_exists "businessUnits/${unit}"; then
            printf "\nDeleting the business unit %s...\n" "${unit}"
            ar_admin_delete "businessUnits/${unit}" || failed=1
        else
            printf "\nThe business unit %s is not there.\n" "${unit}"
        fi
    done
    return "${failed}"
}

if [ "${MODE}" = "remove" ]; then
    remove_all
    exit $?
fi

# A time-stamp for the counts: only transfers after it are counted
RUN_START=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

printf "=== Step 1: the business units ===\n"
for i in 0 1; do
    unit="${BU_NAMES[i]}"
    if ar_admin_exists "businessUnits/${unit}"; then
        printf "The business unit %s is already there. Reused.\n" "${unit}"
        continue
    fi
    printf "Creating the business unit %s, base folder %s/%s...\n" "${unit}" "${BT_HOME_ROOT}" "${unit}"
    ar_admin_post "businessUnits" "$(jq -n --arg name "${unit}" --arg folder "${BT_HOME_ROOT}/${unit}" '{name: $name, baseFolder: $folder}')" \
      || { printf "Stopped: the business unit %s could not be created.\n" "${unit}"; exit 1; }
done

printf "\n=== Step 2: the transfers of each user ===\n"
for i in 0 1; do
    for user in $(unit_users "${BU_NAMES[i]}" "${BU_COUNTS[i]}"); do
        printf "\n--- %s, in %s ---\n" "${user}" "${BU_NAMES[i]}"
        LOG=$(mktemp)
        BT_RUN_BUSINESS_UNIT="${BU_NAMES[i]}" bash "${SCRIPT_DIR}/00.run_all.sh" "${user}" > "${LOG}" 2>&1
        RC=$?
        # Only the analysis of the run, not its whole output
        sed -n '/^=== Step 4/,$p' "${LOG}" | sed '/^Run .*99.cleanup/d'
        if [ "${RC}" -ne 0 ]; then
            printf "\nStopped: the run of %s failed. The last lines of its output:\n" "${user}"
            tail -n 15 "${LOG}"
            rm -f "${LOG}"
            printf "Nothing was cleaned up. ./run_business_units.sh --remove removes it all.\n"
            exit 1
        fi
        rm -f "${LOG}"
    done
done

# transfer_count ACCOUNT [BILLABLE]: the transfers of an account since the start of this run
transfer_count() {
    local billable=()
    [ -n "$2" ] && billable=(--data-urlencode "isBillable=true")
    curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
      "${billable[@]}" \
      --data-urlencode "account=$1" \
      --data-urlencode "startTimeAfter=${RUN_START}" \
      --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
      | jq -r '.resultSet.totalCount // empty' 2>/dev/null
}

# What the rule predicts a user adds: FILES is every file it pulls (inbound only, in and out,
# and 5 more from 2.3 to 2.6), and the account has FILES inbound plus 5 billable pushes
FILES=$((BT_INBOUND_ONLY_COUNT + BT_IN_AND_OUT_COUNT + 5))
PREDICT_BILLABLE=$((FILES + 5))

printf "\n=== Step 3: the transfers of each business unit, since this run started ===\n"
printf "\n  %-20s %6s %14s %14s  %s\n" "business unit" "users" "all transfers" "billable" "the rule predicts (billable)"
MATCHED=1
for i in 0 1; do
    total_all=0; total_billable=0; readable=1
    for user in $(unit_users "${BU_NAMES[i]}" "${BU_COUNTS[i]}"); do
        all=$(transfer_count "${user}")
        billable=$(transfer_count "${user}" billable)
        if [ -z "${all}" ] || [ -z "${billable}" ]; then readable=0; continue; fi
        total_all=$((total_all + all))
        total_billable=$((total_billable + billable))
    done
    predicted=$((PREDICT_BILLABLE * BU_COUNTS[i]))
    if [ "${readable}" -eq 0 ]; then
        printf "  %-20s %6s %14s %14s  %s\n" "${BU_NAMES[i]}" "${BU_COUNTS[i]}" "?" "?" "${predicted}"
        MATCHED=0
        continue
    fi
    [ "${total_billable}" -eq "${predicted}" ] || MATCHED=0
    printf "  %-20s %6s %14s %14s  %s%s\n" "${BU_NAMES[i]}" "${BU_COUNTS[i]}" "${total_all}" "${total_billable}" "${predicted}" \
      "$([ "${total_billable}" -eq "${predicted}" ] && printf '' || printf '   differs')"
done
printf "\nEach user does the transfers of one 00.run_all.sh run, so a unit's count is its number of users\n"
printf "times one run's: the two units differ by their number of users.\n"
if [ "${MATCHED}" -ne 1 ]; then
    printf "A unit did not add what the rule predicts, or a count could not be read. A push still under\n"
    printf "way when this was counted shows up in a later count: ./billable_GET_report.sh <user> shows each user.\n"
fi

if [ "${MODE}" = "cleanup" ]; then
    printf "\n=== Cleanup ===\n"
    remove_all
    exit $?
fi
printf "\nRun ./run_business_units.sh --remove to remove everything this created.\n"
[ "${MATCHED}" -eq 1 ]
