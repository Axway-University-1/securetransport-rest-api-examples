#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole test, start to finish:
#
#   1. Prints today's billable transfer count, and the six days before it
#      (billable_GET_report.sh "before").
#   2. Sets up the account, the sites, the folders, the application, the
#      routes and the subscriptions (01 to 09), uploads the sample files and
#      the two archives (10), and runs the six pulls (11).
#   3. Prints the same report again (billable_GET_report.sh "after"), so
#      today's count can be compared against step 1.
#   4. Prints the real before/after delta for today - how many billable
#      transfers this run actually added - and restates the rule. It does not
#      print a fixed per-scenario table: see the Notes below for why.
#
# Usage:
# ./00.run_all.sh              steps 1 to 4, leaves everything in place
# ./00.run_all.sh --cleanup    the same, then removes everything (99)
#
# Notes:
# - It stops at the first setup step that fails: a non-zero exit, or a line
#   starting HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing
#   is cleaned up, so you can look.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Step 4 used to print a fixed table of the billable count the rule predicts
#   per scenario. That table was wrong, and is gone: billing here is tracked
#   per transfer chain (coreId), not per filename, and step 10's own upload (a
#   real, billable Inbound in its own right) and the pull that empties the drop
#   folder (that chain's own free first outbound) are each a SEPARATE chain from
#   the scenario's intended pull/push, adding billable transfers the rule's
#   plain six-scenario description never counted. Confirmed directly, by
#   comparing this run's own File Tracking entries by coreId. Read the actual
#   result in File Tracking, grouped by Transfer name, rather than trusting a
#   static prediction.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

CLEANUP=0
case "$1" in
    "")        ;;
    --cleanup) CLEANUP=1 ;;
    *)         printf "Usage: ./00.run_all.sh [--cleanup]\n"; exit 2 ;;
esac

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

printf "\n=== Step 1: billable transfers before this run ===\n"
REPORT_LOG=$(mktemp)
bash "${SCRIPT_DIR}/billable_GET_report.sh" "before" | tee "${REPORT_LOG}"
BEFORE_TODAY=$(sed -n 's/^TODAY_COUNT: //p' "${REPORT_LOG}")
rm -f "${REPORT_LOG}"

# Every numbered setup step, except this script and the cleanup
STEPS=()
for f in "${SCRIPT_DIR}"/[0-9][0-9].*.sh; do
    case "$(basename "${f}")" in
        00.*|99.*) ;;
        *)         STEPS+=("${f}") ;;
    esac
done

TOTAL=${#STEPS[@]}
N=0
printf "\n=== Step 2: perform the transfers ===\n"
for step in "${STEPS[@]}"; do
    N=$((N + 1))
    NAME=$(basename "${step}")
    printf "\n--- %s of %s: %s ---\n" "${N}" "${TOTAL}" "${NAME}"

    LOG=$(mktemp)
    bash "${step}" 2>&1 | tee "${LOG}"
    RC=${PIPESTATUS[0]}

    if [ "${RC}" -ne 0 ] || grep -qE '^HTTP [45][0-9][0-9]' "${LOG}"; then
        rm -f "${LOG}"
        printf "\nStopped at step %s of %s: %s failed.\n" "${N}" "${TOTAL}" "${NAME}"
        printf "Nothing after it was run, and nothing was cleaned up.\n"
        printf "Fix it, run ./99.cleanup_DELETE.sh, and start again.\n"
        exit 1
    fi
    rm -f "${LOG}"

    # The pull (11) triggers routes and pushes that run asynchronously
    case "${NAME}" in
        11.*)
            printf "\nPausing %s seconds...\n" "${BT_STEP_PAUSE_SECONDS}"
            sleep "${BT_STEP_PAUSE_SECONDS}"
            ;;
    esac
done

bash "${SCRIPT_DIR}/12.files_GET_result.sh"

printf "\n=== Step 3: billable transfers after this run ===\n"
REPORT_LOG=$(mktemp)
bash "${SCRIPT_DIR}/billable_GET_report.sh" "after" | tee "${REPORT_LOG}"
AFTER_TODAY=$(sed -n 's/^TODAY_COUNT: //p' "${REPORT_LOG}")
rm -f "${REPORT_LOG}"

printf "\n=== Step 4: analysis ===\n"
if [ -n "${BEFORE_TODAY}" ] && [ -n "${AFTER_TODAY}" ]; then
    DELTA=$((AFTER_TODAY - BEFORE_TODAY))
    printf "Today's billable count for %s: %s before this run, %s after.\n" \
      "${BT_TEST_ACCOUNT}" "${BEFORE_TODAY}" "${AFTER_TODAY}"
    printf "This run added %s billable transfer(s) today.\n" "${DELTA}"
else
    printf "Could not read today's count from step 1 or step 3 above; see those for the raw response.\n"
fi
printf "\nThe rule, from the Admin Guide: every inbound transfer is billable. For a\n"
printf "given file, the first outbound transfer that follows it is not billable;\n"
printf "every outbound transfer after that first one is.\n"
printf "\nThat rule is tracked per transfer chain (coreId), not per filename. Step 10's\n"
printf "own upload into outbound-drop is a real, billable Inbound transfer in its own\n"
printf "right, and the pull that later empties outbound-drop is THAT chain's own free\n"
printf "first outbound - both separate from, and in addition to, the scenario's\n"
printf "intended pull into subscription/sN and push to a partner. For the exact\n"
printf "breakdown, read File Tracking for %s, grouped by Transfer name.\n" "${BT_TEST_ACCOUNT}"

if [ "${CLEANUP}" -eq 1 ]; then
    printf "\n=== Cleanup: 99.cleanup_DELETE.sh ===\n"
    bash "${SCRIPT_DIR}/99.cleanup_DELETE.sh"
else
    printf "\nRun ./99.cleanup_DELETE.sh to remove everything this created.\n"
fi
